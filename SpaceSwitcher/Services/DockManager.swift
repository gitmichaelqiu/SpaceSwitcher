import Foundation
import Combine
import AppKit
import os.log

class DockManager: ObservableObject {
    @Published var config: DockConfig = DockConfig() {
        didSet {
            saveConfig()
            // Reset optimization cache if default changes
            if config.defaultDockSetID != oldValue.defaultDockSetID {
                lastAppliedDockSetID = nil
                // If the default changed, we might want to reflect that the currently active set
                // might no longer match the "logic" of what should be active, though we don't
                // force a switch immediately to avoid jarring UX.
            }
        }
    }
    
    // UI STATE: Exposed for Sidebar Highlighting
    @Published var activeDockSetID: UUID?
    
    // OPTIMIZATION: Tracks what we *think* the Dock is currently showing
    private var lastAppliedDockSetID: UUID?
    
    // CONCURRENCY: Tracks the current switching task
    private var dockTask: Task<Void, Never>?
    
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let configKey = "SpaceSwitcherDockConfig"
    
    // LOGGER: Debugging
    private let logger = Logger(subsystem: "com.michaelqiu.SpaceSwitcher", category: "DockManager")
    
    init() {
        loadConfig()
    }
    
    private func setupBindings() {
        spaceManager?.$currentSpaceID
            .removeDuplicates()
            .sink { [weak self] spaceID in
                guard let self = self, let spaceID = spaceID else { return }
                self.applyDockForSpace(spaceID)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Application Logic
    
    /// Triggers a dock switch for a specific space.
    /// - Parameters:
    ///   - spaceID: The UUID string of the target space.
    ///   - force: If true, bypasses debounce and optimization checks (used for "Apply" button).
    func applyDockForSpace(_ spaceID: String, force: Bool = false) {
        // 1. Cancel any pending switch to handle rapid swiping
        dockTask?.cancel()
        
        dockTask = Task {
            // 2. Prevent App Nap: Tell macOS this is critical user-initiated work
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "DockSwitch-\(spaceID)"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            
            // 3. Debounce: Wait for user to settle (only if not forced)
            if !force {
                try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s
            }
            
            if Task.isCancelled { return }
            
            // 4. Perform
            await performDockSwitch(for: spaceID, force: force)
        }
    }
    
    @MainActor
    private func performDockSwitch(for spaceID: String, force: Bool) async {
        let targetSetID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
        
        guard let setID = targetSetID else {
            logger.debug("No dock assigned for space \(spaceID), and no default set.")
            return
        }
        
        // OPTIMIZATION: Skip if already active (unless forced or switching to default)
        // We generally allow re-applying default to ensure consistency, but strictly skip custom sets.
        let isSwitchingToDefault = (setID == config.defaultDockSetID)
        if !force && !isSwitchingToDefault && setID == lastAppliedDockSetID {
            logger.debug("Already on Dock Set \(setID), skipping.")
            // Ensure UI is in sync even if we skipped the work
            if activeDockSetID != setID { activeDockSetID = setID }
            return
        }
        
        guard let set = config.dockSets.first(where: { $0.id == setID }) else { return }
        
        logger.info(">>> \(force ? "FORCED" : "STARTING") SWITCH: '\(set.name)' for Space \(spaceID)")
        
        // Run the heavy I/O and Process logic
        let success = await applyDockSetVerified(set)
        
        if success {
            self.lastAppliedDockSetID = set.id
            self.activeDockSetID = set.id
            logger.info("<<< SUCCESS: Switched to '\(set.name)'")
        } else {
            logger.error("<<< FAILURE: Could not verify dock write for '\(set.name)'")
        }
    }
    
    // MARK: - Core System Logic (Verified Write + Force Kill)
    
    private func applyDockSetVerified(_ set: DockSet) async -> Bool {
        return await Task.detached(priority: .userInitiated) {
            let key = "persistent-apps" as CFString
            let appID = "com.apple.dock" as CFString
            
            // 1. Prepare Data
            let rawData = await self.buildRawDockData(from: set.tiles)
            let targetCount = rawData.count
            
            // 2. Write & Verify Loop (Max 5 attempts)
            var verified = false
            for attempt in 1...5 {
                // A. WRITE
                CFPreferencesSetAppValue(key, rawData as CFPropertyList, appID)
                let syncResult = CFPreferencesAppSynchronize(appID)
                
                if !syncResult {
                    self.logger.error("Attempt \(attempt): CFPreferencesAppSynchronize returned FALSE")
                }
                
                // B. WAIT (Give cfprefsd time to flush) - Increases with attempts
                let delay = UInt32(150_000 + (attempt * 50_000))
                usleep(delay)
                
                // C. READ BACK (Verification)
                CFPreferencesAppSynchronize(appID) // Force re-sync before read
                
                if let readVal = CFPreferencesCopyAppValue(key, appID) as? [Any] {
                    // Simple count check usually suffices, but we check first item for robustness
                    if readVal.count == targetCount {
                        if targetCount == 0 {
                            // Empty dock matched
                            self.logger.info("Attempt \(attempt): Verification PASSED (Empty Dock).")
                            verified = true
                            break
                        }
                        
                        // Check first item label
                        if let firstTarget = rawData.first as? [String: Any],
                           let firstRead = readVal.first as? [String: Any],
                           let targetLabel = (firstTarget["tile-data"] as? [String: Any])?["file-label"] as? String,
                           let readLabel = (firstRead["tile-data"] as? [String: Any])?["file-label"] as? String,
                           targetLabel == readLabel {
                            
                            self.logger.info("Attempt \(attempt): Verification PASSED. (Items: \(targetCount))")
                            verified = true
                            break
                        }
                    }
                    self.logger.warning("Attempt \(attempt): Verification FAILED. Read \(readVal.count), expected \(targetCount). Retrying...")
                } else {
                    self.logger.warning("Attempt \(attempt): Read-back returned nil.")
                }
            }
            
            if !verified {
                self.logger.fault("CRITICAL: Failed to verify dock preferences after 5 attempts. Aborting kill.")
                return false
            }
            
            // 3. KILL DOCK (FORCE KILL)
            // We use -KILL (SIGKILL) to prevent the Dock from saving its state on exit.
            self.logger.info("Restarting Dock process (SIGKILL)...")
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["-KILL", "Dock"]
            task.launch()
            task.waitUntilExit()
            
            return true
        }.value
    }
    
    // MARK: - Data Management & Spacers
    
    func createNewDockSet(name: String) {
        guard let rawApps = getSystemDockPersistentApps() else { return }
        let tiles = parseRawDockData(rawApps)
        DispatchQueue.main.async {
            let newSet = DockSet(id: UUID(), name: name, dateCreated: Date(), tiles: tiles)
            self.config.dockSets.append(newSet)
            if self.config.defaultDockSetID == nil { self.config.defaultDockSetID = newSet.id }
        }
    }
    
    func createTile(from url: URL) -> DockTile {
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = Bundle(url: url)?.bundleIdentifier
        let tileData: [String: Any] = [
            "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
            "file-label": name,
            "bundle-identifier": bundleID ?? "",
            "file-type": 41
        ]
        let raw: [String: Any] = ["tile-data": tileData, "tile-type": "file-tile"]
        return DockTile(label: name, bundleIdentifier: bundleID, fileURL: url, rawData: raw)
    }

    /// Creates a spacer tile.
    /// - Parameter isSmall: If true, creates a small spacer (often used as a separator).
    func createSpacerTile(isSmall: Bool) -> DockTile {
        let type = isSmall ? "small-spacer-tile" : "spacer-tile"
        let label = isSmall ? "Small Spacer" : "Large Spacer"
        
        let rawData: [String: Any] = [
            "tile-data": [:], // Spacers have empty data
            "tile-type": type
        ]
        
        return DockTile(label: label, bundleIdentifier: nil, fileURL: nil, rawData: rawData)
    }
    
    // MARK: - Internal Helpers
    
    private func getSystemDockPersistentApps() -> [Any]? {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        return defaults?.array(forKey: "persistent-apps")
    }
    
    private func parseRawDockData(_ rawArray: [Any]) -> [DockTile] {
        var tiles: [DockTile] = []
        for case let itemDict as [String: Any] in rawArray {
            // 1. Detect Type
            let tileType = itemDict["tile-type"] as? String
            
            // 2. Extract Data
            var label = "Unknown"
            var bundleID: String? = nil
            var url: URL? = nil
            
            if let tileData = itemDict["tile-data"] as? [String: Any] {
                if tileType == "spacer-tile" {
                    label = "Large Spacer"
                } else if tileType == "small-spacer-tile" {
                    label = "Small Spacer"
                } else {
                    label = tileData["file-label"] as? String ?? "Unknown"
                    bundleID = tileData["bundle-identifier"] as? String
                    if let urlStr = tileData["file-data"] as? [String: Any],
                       let path = urlStr["_CFURLString"] as? String {
                        url = URL(string: path)
                    }
                }
            }
            
            tiles.append(DockTile(
                label: label,
                bundleIdentifier: bundleID,
                fileURL: url,
                rawData: itemDict
            ))
        }
        return tiles
    }
    
    private func buildRawDockData(from tiles: [DockTile]) -> [Any] {
        return tiles.map { $0.rawData }
    }
    
    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(DockConfig.self, from: data) {
            config = decoded
        }
    }
    
    private func saveConfig() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: configKey)
        }
    }
}

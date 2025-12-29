import Foundation
import Combine
import AppKit
import os.log

class DockManager: ObservableObject {
    @Published var config: DockConfig = DockConfig() {
        didSet {
            saveConfig()
            if config.defaultDockSetID != oldValue.defaultDockSetID {
                lastAppliedDockSetID = nil
            }
        }
    }
    
    private var lastAppliedDockSetID: UUID?
    private var dockTask: Task<Void, Never>?
    
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let configKey = "SpaceSwitcherDockConfig"
    
    // DEBUG LOGGER
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
    
    // MARK: - Logic
    
    func applyDockForSpace(_ spaceID: String) {
        dockTask?.cancel()
        
        dockTask = Task {
            // 1. Prevent App Nap
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "DockSwitch-\(spaceID)"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            
            // 2. Debounce (Allow rapid swiping)
            try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s
            if Task.isCancelled { return }
            
            await performDockSwitch(for: spaceID)
        }
    }
    
    @MainActor
    private func performDockSwitch(for spaceID: String) async {
        let targetSetID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
        guard let setID = targetSetID else {
            logger.debug("No dock assigned for space \(spaceID), and no default set.")
            return
        }
        
        // Skip if already applied
        if setID == lastAppliedDockSetID && setID != config.defaultDockSetID {
            logger.debug("Already on Dock Set \(setID), skipping.")
            return
        }
        
        guard let set = config.dockSets.first(where: { $0.id == setID }) else { return }
        
        logger.info(">>> STARTING SWITCH: '\(set.name)' for Space \(spaceID)")
        
        // Run blocking I/O on background thread
        let success = await applyDockSetVerified(set)
        
        if success {
            self.lastAppliedDockSetID = set.id
            logger.info("<<< SUCCESS: Switched to '\(set.name)'")
        } else {
            logger.error("<<< FAILURE: Could not verify dock write for '\(set.name)'")
        }
    }
    
    // MARK: - Core Logic (Verified Write + Force Kill)
    
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
                
                // B. WAIT (Give cfprefsd time to flush)
                // let delay = UInt32(150_000 + (attempt * 50_000))
                // usleep(delay)
                
                // C. READ BACK (Verification)
                CFPreferencesAppSynchronize(appID) // Force re-sync before read
                
                if let readVal = CFPreferencesCopyAppValue(key, appID) as? [Any] {
                    if readVal.count == targetCount {
                        // Deep check first item
                        if let firstTarget = rawData.first as? [String: Any],
                           let firstRead = readVal.first as? [String: Any],
                           let targetLabel = (firstTarget["tile-data"] as? [String: Any])?["file-label"] as? String,
                           let readLabel = (firstRead["tile-data"] as? [String: Any])?["file-label"] as? String,
                           targetLabel == readLabel {
                            
                            self.logger.info("Attempt \(attempt): Verification PASSED. (Items: \(targetCount))")
                            verified = true
                            break
                        } else if targetCount == 0 {
                            self.logger.info("Attempt \(attempt): Verification PASSED (Empty Dock).")
                            verified = true
                            break
                        }
                    }
                    self.logger.warning("Attempt \(attempt): Verification FAILED. Read \(readVal.count) items, expected \(targetCount). Retrying...")
                } else {
                    self.logger.warning("Attempt \(attempt): Read-back returned nil.")
                }
            }
            
            if !verified {
                self.logger.fault("CRITICAL: Failed to verify dock preferences after 5 attempts. Aborting kill.")
                return false
            }
            
            // 3. KILL DOCK (FORCE KILL FIX)
            self.logger.info("Restarting Dock process (SIGKILL)...")
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            
            // FIX IS HERE: Add "-KILL" to force immediate termination
            // This prevents the Dock from saving its current state on exit.
            task.arguments = ["-KILL", "Dock"]
            
            task.launch()
            task.waitUntilExit()
            
            return true
        }.value
    }
    
    func createNewDockSet(name: String) {
        guard let rawApps = getSystemDockPersistentApps() else { return }
        let tiles = parseRawDockData(rawApps)
        DispatchQueue.main.async {
            let newSet = DockSet(id: UUID(), name: name, dateCreated: Date(), tiles: tiles)
            self.config.dockSets.append(newSet)
            if self.config.defaultDockSetID == nil { self.config.defaultDockSetID = newSet.id }
        }
    }
    
    private func getSystemDockPersistentApps() -> [Any]? {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        return defaults?.array(forKey: "persistent-apps")
    }

    // MARK: - Spacer Creation (NEW)
    func createSpacerTile(isSmall: Bool) -> DockTile {
        let type = isSmall ? "small-spacer-tile" : "spacer-tile"
        let label = isSmall ? "Small Spacer" : "Large Spacer"
        
        // Spacers use a simple dictionary structure
        let rawData: [String: Any] = [
            "tile-data": [:], // Empty dict for data
            "tile-type": type
        ]
        
        return DockTile(label: label, bundleIdentifier: nil, fileURL: nil, rawData: rawData)
    }

    // MARK: - Helpers
    private func parseRawDockData(_ rawArray: [Any]) -> [DockTile] {
        var tiles: [DockTile] = []
        for case let itemDict as [String: Any] in rawArray {
            // 1. Check tile type first
            let tileType = itemDict["tile-type"] as? String
            
            // 2. Default extraction
            var label = "Unknown"
            var bundleID: String? = nil
            var url: URL? = nil
            
            if let tileData = itemDict["tile-data"] as? [String: Any] {
                // If it's a spacer, override the label
                if tileType == "spacer-tile" {
                    label = "Large Spacer"
                } else if tileType == "small-spacer-tile" {
                    label = "Small Spacer"
                } else {
                    // Regular App/File logic
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

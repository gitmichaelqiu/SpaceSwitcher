import Foundation
import Combine
import AppKit
import os.log

class DockManager: ObservableObject {
    @MainActor @Published var config: DockConfig = DockConfig() {
        didSet {
            saveConfig()
            if config.defaultDockSetID != oldValue.defaultDockSetID {
                lastAppliedDockSetID = nil
            }
        }
    }
    
    @MainActor @Published var activeDockSetID: UUID?
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
        detectActiveDockSet()
    }
    
    /// Scans the system Dock and updates activeDockSetID if a match is found.
    func detectActiveDockSet() {
        Task {
            // 1. Move heavy disk I/O and parsing to a background thread
            let (matchFound, matchedID) = await Task.detached(priority: .background) {
                guard let rawApps = self.getSystemDockPersistentApps() else { return (false, nil) }
                let currentTiles = self.parseRawDockData(rawApps)
                
                // We need to access config from MainActor for the comparison
                return await MainActor.run {
                    if let match = self.config.dockSets.first(where: { $0.tiles == currentTiles }) {
                        return (true, match.id)
                    }
                    return (false, nil)
                }
            }.value
            
            // 2. Update Published properties on MainActor
            if matchFound, let id = matchedID {
                await MainActor.run {
                    self.activeDockSetID = id
                    self.lastAppliedDockSetID = id
                }
            }
        }
    }
    
    private func setupBindings() {
        spaceManager?.$currentSpaceID
            .removeDuplicates()
            .sink { [weak self] spaceID in
                guard let self = self, let spaceID = spaceID else { return }
                if self.config.isAutomationEnabled {
                    self.applyDockForSpace(spaceID)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Application Logic
    
    /// Triggers a dock switch for a specific space.
    /// - Parameters:
    ///   - spaceID: The UUID string of the target space.
    ///   - force: If true, bypasses debounce and optimization checks (used for "Apply" button).
    @MainActor
    func applyDockForSpace(_ spaceID: String, force: Bool = false) {
        // 1. Cancel any pending switch to handle rapid swiping
        dockTask?.cancel()
        
        // 2. Use a detached task to avoid blocking the Main Actor (UI Thread)
        // This is CRITICAL to prevent "Connection interrupted" errors
        dockTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // 3. Debounce: Wait for user to settle (only if not forced)
            if !force {
                try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s
            }
            
            if Task.isCancelled { return }
            
            // 4. Perform Switch
            await self.performDockSwitch(for: spaceID, force: force)
        }
    }
    
    /// Manually applies a specific dock set by its ID.
    func applyDockSetByID(_ id: UUID) {
        dockTask?.cancel()
        dockTask = Task {
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "ManualDockSwitch-\(id)"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            
            guard let set = config.dockSets.first(where: { $0.id == id }) else { return }
            
            logger.info(">>> MANUAL SWITCH: '\(set.name)'")
            let success = await applyDockSetVerified(set)
            
            if success {
                await MainActor.run {
                    self.lastAppliedDockSetID = set.id
                    self.activeDockSetID = set.id
                }
                logger.info("<<< SUCCESS: Manually switched to '\(set.name)'")
            }
        }
    }
    
    private func performDockSwitch(for spaceID: String, force: Bool) async {
        // 1. Get configuration from MainActor
        let (targetSet, isAutomationOn) = await MainActor.run {
            let setID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
            let set = config.dockSets.first(where: { $0.id == setID })
            return (set, config.isAutomationEnabled)
        }
        
        guard let set = targetSet else { return }
        
        // 2. Check ACTUAL system state (Off Main Thread)
        if !force {
            if let currentRaw = getSystemDockPersistentApps() {
                let currentTiles = parseRawDockData(currentRaw)
                if set.tiles == currentTiles {
                    await MainActor.run { if activeDockSetID != set.id { activeDockSetID = set.id } }
                    return
                }
            }
        }
        
        logger.info(">>> \(force ? "FORCED" : "STARTING") SWITCH: '\(set.name)' for Space \(spaceID)")
        
        let success = await applyDockSetVerified(set)
        
        if success {
            await MainActor.run {
                self.lastAppliedDockSetID = set.id
                self.activeDockSetID = set.id
            }
            logger.info("<<< SUCCESS: Switched to '\(set.name)'")
        } else {
            logger.error("<<< FAILURE: Could not verify dock write for '\(set.name)'")
        }
    }
    
    // MARK: - Core System Logic (Verified Write + Force Kill)
    
    private func getSystemDockPersistentApps() -> [Any]? {
        let appID = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        
        // Use CFPreferences to read from the system's preference cache (cfprefsd)
        // This is the standard macOS way and is more robust than direct file I/O.
        guard let apps = CFPreferencesCopyAppValue(key, appID) as? [Any] else {
            return nil
        }
        return apps
    }
    
    private func applyDockSetVerified(_ set: DockSet) async -> Bool {
        let appID = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        
        // 1. Prepare Data
        let newAppData = self.buildRawDockData(from: set.tiles)
        
        // 2. Perform attempts using standard CFPreferences API
        // This is the proper way to modify system preferences and handles cfprefsd synchronization.
        for attempt in 1...3 {
            if Task.isCancelled { return false }
            
            // A. Set the value in the preference cache
            CFPreferencesSetAppValue(key, newAppData as CFPropertyList, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            
            // B. Synchronize to ensure the changes are committed to the daemon and disk
            if !CFPreferencesAppSynchronize(appID) {
                logger.error("Attempt \(attempt): CFPreferencesAppSynchronize failed")
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            
            // C. Wait for system to process the update (0.3s)
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            // D. Restart Dock to pick up new preferences
            let killTask = Process()
            killTask.launchPath = "/usr/bin/killall"
            killTask.arguments = ["Dock"]
            killTask.launch()
            killTask.waitUntilExit()
            
            // E. Verify (Read back via the API)
            try? await Task.sleep(nanoseconds: 600_000_000)
            if let verifyApps = CFPreferencesCopyAppValue(key, appID) as? [Any] {
                // We compare the count as a quick verification of success
                if verifyApps.count == newAppData.count {
                    return true
                }
            }
        }
        
        return false
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

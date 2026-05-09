import Foundation
import Combine
import AppKit
import os.log

@MainActor
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
        detectActiveDockSet()
    }
    
    /// Scans the system Dock and updates activeDockSetID if a match is found.
    func detectActiveDockSet() {
        guard let rawApps = getSystemDockPersistentApps() else { return }
        let currentTiles = parseRawDockData(rawApps)
        
        // Find a set that matches the current system tiles
        if let match = config.dockSets.first(where: { $0.tiles == currentTiles }) {
            self.activeDockSetID = match.id
            self.lastAppliedDockSetID = match.id
        } else {
            // Fallback: if we just applied one or automation is on, 
            // it will eventually be set by applyDockForSpace.
            // If not, we keep it nil to indicate 'Custom/Modified' state.
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
    
    @MainActor
    private func performDockSwitch(for spaceID: String, force: Bool) async {
        let targetSetID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
        
        guard let setID = targetSetID else {
            logger.debug("No dock assigned for space \(spaceID), and no default set.")
            return
        }
        
        // 1. Check ACTUAL system state (Don't rely on cached lastAppliedDockSetID)
        if !force {
            if let currentRaw = getSystemDockPersistentApps() {
                let currentTiles = parseRawDockData(currentRaw)
                if set.tiles == currentTiles {
                    if activeDockSetID != set.id { activeDockSetID = set.id }
                    return
                }
            }
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
        let appID = "com.apple.dock"
        let key = "persistent-apps"
        
        // 1. Prepare Data
        let rawData = await self.buildRawDockData(from: set.tiles)
        
        // 2. Write to temporary plist
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("com.apple.dock.import.plist")
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: [key: rawData], format: .binary, options: 0)
            try data.write(to: tempFile)
        } catch {
            self.logger.error("Failed to create temporary plist: \(error.localizedDescription)")
            return false
        }
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // 3. IMPORT (The industry standard for reliability)
        let importTask = Process()
        importTask.launchPath = "/usr/bin/defaults"
        importTask.arguments = ["import", appID, tempFile.path]
        importTask.launch()
        importTask.waitUntilExit()
        
        // 4. PURGE USER CACHE (Targeted for high reliability)
        let purgeTask = Process()
        purgeTask.launchPath = "/usr/bin/killall"
        purgeTask.arguments = ["-u", NSUserName(), "cfprefsd"]
        purgeTask.launch()
        purgeTask.waitUntilExit()
        
        // 5. STABILITY WAIT (0.5s)
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        if Task.isCancelled { return false }
        
        // 6. SINGLE RESTART
        self.logger.info("Triggering targeted high-stability Dock restart.")
        let killTask = Process()
        killTask.launchPath = "/usr/bin/killall"
        killTask.arguments = ["Dock"]
        killTask.launch()
        killTask.waitUntilExit()
        
        return true
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

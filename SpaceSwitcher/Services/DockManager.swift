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
    
    // Serializes access to applyDockSetVerified to prevent concurrent Dock restarts
    private let switchLock = NSLock()

    // Tracks the current switching task
    private var dockTask: Task<Void, Never>?
    
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let configKey = "SpaceSwitcherDockConfig"
    
    // Logger for debugging
    private let logger = Logger(subsystem: "com.michaelqiu.SpaceSwitcher", category: "DockManager")
    
    init() {
        loadConfig()
        detectActiveDockSet()
    }
    
    /// Scans the system Dock and updates activeDockSetID if a match is found.
    func detectActiveDockSet() {
        Task {
            // Move heavy disk I/O and parsing to a background thread
            let (matchFound, matchedID): (Bool, UUID?) = await Task.detached(priority: .background) {
                guard let rawApps = DockManager.getSystemDockPersistentApps() else { return (false, nil) }
                let currentTiles = DockManager.parseRawDockData(rawApps)
                
                // We need to access config from MainActor for the comparison
                return await MainActor.run {
                    if let match = self.config.dockSets.first(where: { $0.tiles == currentTiles }) {
                        return (true, match.id)
                    }
                    return (false, nil)
                }
            }.value
            
            // Update Published properties on MainActor
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
        // Cancel any pending switch to handle rapid swiping
        dockTask?.cancel()
        
        // Use a detached task to prevent blocking the Main Actor.
        // Prevents "Connection interrupted" errors during rapid switches.
        dockTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Debounce to allow space transitions to settle
            if !force {
                try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s
            }
            
            if Task.isCancelled { return }
            
            // Perform the Dock switch
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
        // Get configuration from MainActor
        let (targetSet, _) = await MainActor.run {
            let setID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
            let set = config.dockSets.first(where: { $0.id == setID })
            return (set, config.isAutomationEnabled)
        }
        
        guard let set = targetSet else { return }
        
        // Check system state off the main thread
        if !force {
            if let currentRaw = DockManager.getSystemDockPersistentApps() {
                let currentTiles = DockManager.parseRawDockData(currentRaw)
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
    
    nonisolated static private func getSystemDockPersistentApps() -> [Any]? {
        let appID = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString

        guard let apps = CFPreferencesCopyAppValue(key, appID) as? [Any] else {
            return nil
        }
        return apps
    }

    /// Reads persistent-apps directly from the Dock plist file, bypassing cfprefsd.
    /// Used for verification after Dock restart when cfprefsd XPC connections
    /// may be broken (producing "Connection interrupted" errors).
    nonisolated static private func readPersistentAppsFromDisk() -> [Any]? {
        let path = NSHomeDirectory() + "/Library/Preferences/com.apple.dock.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let apps = plist["persistent-apps"] as? [Any]
        else { return nil }
        return apps
    }

    /// Writes persistent-apps directly to the Dock plist file, bypassing cfprefsd.
    /// Ensures the new tile data is physically on disk before the Dock is killed,
    /// eliminating race conditions with cfprefsd async sync and the "Connection interrupted"
    /// errors that occur when the Dock is restarted while cfprefsd XPC is broken.
    nonisolated static private func writePersistentAppsToDisk(_ apps: [Any]) throws {
        let path = NSHomeDirectory() + "/Library/Preferences/com.apple.dock.plist"

        // Preserve existing Dock settings (orientation, magnify, etc.) by
        // reading the current plist and only replacing the persistent-apps key.
        var plist: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let existing = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            plist = existing
        }

        plist["persistent-apps"] = apps

        let newData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try newData.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    
    private func applyDockSetVerified(_ set: DockSet) async -> Bool {
        switchLock.lock()
        defer { switchLock.unlock() }

        if Task.isCancelled { return false }

        let appID = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        let newAppData = DockManager.buildRawDockData(from: set.tiles)
        let expectedLabels = set.tiles.map { $0.label }

        for attempt in 1...3 {
            if Task.isCancelled { return false }

            // 1. Kill Dock FIRST so the dying process can't overwrite
            //    cfprefsd with its in-memory state during shutdown cleanup.
            let oldDockPIDs = Set(NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock")
                .map { $0.processIdentifier })

            logger.info("Attempt \(attempt): killing Dock (PIDs: \(oldDockPIDs))")

            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killTask.arguments = ["Dock"]

            await withTaskCancellationHandler {
                try? killTask.run()
                killTask.waitUntilExit()
            } onCancel: {
                killTask.terminate()
            }

            if killTask.terminationStatus != 0 {
                logger.error("Attempt \(attempt): killall Dock failed (exit \(killTask.terminationStatus))")
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            if Task.isCancelled { return false }

            // 2. Wait for old Dock PIDs to disappear
            for _ in 0..<10 {
                let currentPIDs = Set(NSRunningApplication
                    .runningApplications(withBundleIdentifier: "com.apple.dock")
                    .map { $0.processIdentifier })
                if oldDockPIDs.isDisjoint(with: currentPIDs) { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return false }
            }

            // 3. Grace period for deferred cfprefsd cleanup from old Dock
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return false }

            // 4. Write to cfprefsd (updates the in-memory cache the new
            //    Dock queries on startup) + plist directly as backup
            CFPreferencesSetValue(key, newAppData as CFPropertyList, appID,
                                   kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesAppSynchronize(appID)

            do {
                try DockManager.writePersistentAppsToDisk(newAppData)
            } catch {
                logger.error("Attempt \(attempt): backup plist write failed: \(error.localizedDescription)")
            }

            logger.info("Attempt \(attempt): wrote cfprefsd + plist, waiting for Dock restart")

            // 5. Wait for new Dock process (different PID) to appear
            var newPIDs: Set<pid_t> = []
            for _ in 0..<20 {
                let current = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
                let fresh = Set(current.map { $0.processIdentifier }).subtracting(oldDockPIDs)
                if !fresh.isEmpty { newPIDs = fresh; break }
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return false }
            }

            if newPIDs.isEmpty {
                logger.error("Attempt \(attempt): Dock did not restart")
                continue
            }

            logger.info("Attempt \(attempt): Dock restarted (new PIDs: \(newPIDs))")

            // 6. Let Dock settle
            try? await Task.sleep(nanoseconds: 500_000_000)

            // 7. Verify — read from cfprefsd first (what the Dock actually
            //    sees), fall back to plist if cfprefsd is temporarily down
            for readAttempt in 1...4 {
                if Task.isCancelled { return false }

                var matched = false
                var source = "none"

                if let apps = DockManager.getSystemDockPersistentApps() {
                    let tiles = DockManager.parseRawDockData(apps)
                    matched = tiles == set.tiles
                    source = "cfprefsd"
                    if !matched {
                        logger.warning("Read #\(readAttempt) cfprefsd: got \(tiles.map(\.label)), expected \(expectedLabels)")
                    }
                } else if let apps = DockManager.readPersistentAppsFromDisk() {
                    let tiles = DockManager.parseRawDockData(apps)
                    matched = tiles == set.tiles
                    source = "plist-fallback"
                    if !matched {
                        logger.warning("Read #\(readAttempt) plist: got \(tiles.map(\.label)), expected \(expectedLabels)")
                    }
                } else {
                    logger.warning("Read #\(readAttempt): could not read from cfprefsd or plist")
                }

                if matched {
                    logger.info("Verification passed on read #\(readAttempt) (source: \(source))")
                    return true
                }

                if readAttempt < 4 {
                    try? await Task.sleep(nanoseconds: UInt64(readAttempt) * 400_000_000)
                }
            }

            logger.error("Attempt \(attempt): verification reads exhausted")
        }

        return false
    }
    
    // MARK: - Data Management & Spacers
    
    func createNewDockSet(name: String) {
        guard let rawApps = DockManager.getSystemDockPersistentApps() else { return }
        let tiles = DockManager.parseRawDockData(rawApps)
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
        let rawDict: [String: Any] = ["tile-data": tileData, "tile-type": "file-tile"]
        let blob = (try? PropertyListSerialization.data(fromPropertyList: rawDict, format: .binary, options: 0)) ?? Data()
        
        return DockTile(label: name, bundleIdentifier: bundleID, fileURL: url, rawDataBlob: blob)
    }

    func createSpacerTile(isSmall: Bool) -> DockTile {
        let type = isSmall ? "small-spacer-tile" : "spacer-tile"
        let label = isSmall ? "Small Spacer" : "Large Spacer"
        
        let rawDict: [String: Any] = [
            "tile-data": [:],
            "tile-type": type
        ]
        let blob = (try? PropertyListSerialization.data(fromPropertyList: rawDict, format: .binary, options: 0)) ?? Data()
        
        return DockTile(label: label, bundleIdentifier: nil, fileURL: nil, rawDataBlob: blob)
    }
    
    
    nonisolated static private func parseRawDockData(_ rawArray: [Any]) -> [DockTile] {
        var tiles: [DockTile] = []
        for case let itemDict as [String: Any] in rawArray {
            let tileType = itemDict["tile-type"] as? String
            
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
            
            let blob = (try? PropertyListSerialization.data(fromPropertyList: itemDict, format: .binary, options: 0)) ?? Data()
            
            tiles.append(DockTile(
                label: label,
                bundleIdentifier: bundleID,
                fileURL: url,
                rawDataBlob: blob
            ))
        }
        return tiles
    }
    
    nonisolated static private func buildRawDockData(from tiles: [DockTile]) -> [Any] {
        return tiles.compactMap { tile in
            var format = PropertyListSerialization.PropertyListFormat.binary
            return try? PropertyListSerialization.propertyList(from: tile.rawDataBlob, options: [], format: &format)
        }
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

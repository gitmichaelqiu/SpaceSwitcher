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
    
    // Serializes Dock restart to prevent concurrent killall + verify cycles
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
    ///
    /// Two-phase approach to handle rapid space switching:
    ///   Phase 1 (immediate): Write tiles to plist + cfprefsd + kill cfprefsd.
    ///     This is fast (~1s) and ensures the plist is always up to date.
    ///   Phase 2 (debounced): Kill Dock, wait for restart, verify.
    ///     This is slow (~6s) and only runs after the user pauses switching.
    /// - Parameters:
    ///   - spaceID: The UUID string of the target space.
    ///   - force: If true, bypasses debounce and optimization checks (used for "Apply" button).
    @MainActor
    func applyDockForSpace(_ spaceID: String, force: Bool = false) {
        dockTask?.cancel()

        dockTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // Get target set from MainActor
            let targetSet: DockSet? = await MainActor.run {
                let setID = self.config.spaceAssignments[spaceID] ?? self.config.defaultDockSetID
                return self.config.dockSets.first(where: { $0.id == setID })
            }
            guard let set = targetSet else { return }
            let setName = set.name

            // Skip if already matching
            if !force {
                if let currentRaw = DockManager.getSystemDockPersistentApps() {
                    if DockManager.parseRawDockData(currentRaw) == set.tiles {
                        await MainActor.run { if self.activeDockSetID != set.id { self.activeDockSetID = set.id } }
                        return
                    }
                }
            }

            // Phase 1: Write plist immediately (fast, no debounce).
            // Even if cancelled during Phase 2, the plist stays correct.
            let phase1OK = await self.phase1WriteToDisk(set)
            if Task.isCancelled { return }

            // Debounce before Phase 2 — rapid space switching only
            // re-runs Phase 1. The Dock is only killed when the user
            // pauses long enough.
            if !phase1OK {
                // Phase 2 won't succeed if Phase 1 failed
                logger.error("Phase 1 write failed for '\(setName)'")
                return
            }

            if !force {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            }
            if Task.isCancelled { return }

            // Phase 2: Restart Dock and verify
            logger.info(">>> \(force ? "FORCED" : "STARTING") SWITCH: '\(setName)' for Space \(spaceID)")
            let success = await self.phase2RestartDockAndVerify(set)

            if success {
                await MainActor.run {
                    self.lastAppliedDockSetID = set.id
                    self.activeDockSetID = set.id
                }
                logger.info("<<< SUCCESS: Switched to '\(setName)'")
            } else {
                logger.error("<<< FAILURE: Could not verify dock write for '\(setName)'")
            }
        }
    }

    /// Manually applies a specific dock set by its ID.
    /// Uses the full synchronous flow (no debounce).
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

    // MARK: - Two-Phase Dock Switch

    /// Phase 1: Write tiles to plist + cfprefsd, then kill cfprefsd to force
    /// a fresh read from disk. Fast (~1s), non-disruptive (Dock stays alive).
    private func phase1WriteToDisk(_ set: DockSet) async -> Bool {
        let appID = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        let newAppData = DockManager.buildRawDockData(from: set.tiles)

        // Write to plist (disk ground truth)
        do {
            try DockManager.writePersistentAppsToDisk(newAppData)
        } catch {
            logger.error("Phase 1: plist write failed: \(error.localizedDescription)")
            return false
        }

        // Write to cfprefsd so the cache matches
        CFPreferencesSetValue(key, newAppData as CFPropertyList, appID,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize(appID)

        // Kill cfprefsd to force restart from fresh plist.
        // This prevents cfprefsd from serving stale cached data.
        let oldSet = DockManager.pidsByName("cfprefsd")
        if !oldSet.isEmpty {
            logger.info("Phase 1: killing cfprefsd (PIDs: \(oldSet))")

            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killTask.arguments = ["-u", NSUserName(), "cfprefsd"]

            await withTaskCancellationHandler {
                try? killTask.run()
                killTask.waitUntilExit()
            } onCancel: {
                killTask.terminate()
            }

            // Wait for old PIDs to disappear
            for _ in 0..<10 {
                if Task.isCancelled { return false }
                let current = DockManager.pidsByName("cfprefsd")
                if oldSet.isDisjoint(with: current) { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            // Wait for new cfprefsd to restart
            for _ in 0..<10 {
                if Task.isCancelled { return false }
                let current = DockManager.pidsByName("cfprefsd")
                if !current.isEmpty && oldSet.isDisjoint(with: current) { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            logger.info("Phase 1: cfprefsd restarted")
        }

        return true
    }

    /// Phase 2: Kill Dock, wait for death, then RE-APPLY the plist + cfprefsd
    /// write (because the dying Dock flushes its stale state to cfprefsd during
    /// shutdown, overwriting our Phase 1 data). Then wait for Dock restart and verify.
    private func phase2RestartDockAndVerify(_ set: DockSet) async -> Bool {
        switchLock.lock()
        defer { switchLock.unlock() }

        if Task.isCancelled { return false }

        let appID = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        let newAppData = DockManager.buildRawDockData(from: set.tiles)
        let expectedLabels = set.tiles.map { $0.label }

        for attempt in 1...3 {
            if Task.isCancelled { return false }

            // 1. Kill Dock — its shutdown will flush stale state to cfprefsd,
            //    overwriting our Phase 1 data. We'll re-write after it's dead.
            let oldDockPIDs = Set(NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock")
                .map { $0.processIdentifier })

            logger.info("Phase 2 attempt \(attempt): killing Dock (PIDs: \(oldDockPIDs))")

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
                logger.error("Phase 2 attempt \(attempt): killall Dock failed")
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            if Task.isCancelled { return false }

            // 2. Wait for old Dock PIDs to fully disappear (shutdown complete)
            for _ in 0..<10 {
                let currentPIDs = Set(NSRunningApplication
                    .runningApplications(withBundleIdentifier: "com.apple.dock")
                    .map { $0.processIdentifier })
                if oldDockPIDs.isDisjoint(with: currentPIDs) { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return false }
            }

            // Give the old Dock's cfprefsd flush time to land
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return false }

            // 3. Re-write plist + cfprefsd, then kill cfprefsd.
            //    This overwrites the stale data the dying Dock just flushed.
            do {
                try DockManager.writePersistentAppsToDisk(newAppData)
            } catch {
                logger.error("Phase 2 attempt \(attempt): plist re-write failed: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            CFPreferencesSetValue(key, newAppData as CFPropertyList, appID,
                                   kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesAppSynchronize(appID)

            let oldCfpPIDs = DockManager.pidsByName("cfprefsd")
            if !oldCfpPIDs.isEmpty {
                logger.info("Phase 2 attempt \(attempt): re-killing cfprefsd (PIDs: \(oldCfpPIDs))")

                let killCfp = Process()
                killCfp.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                killCfp.arguments = ["-u", NSUserName(), "cfprefsd"]

                await withTaskCancellationHandler {
                    try? killCfp.run()
                    killCfp.waitUntilExit()
                } onCancel: {
                    killCfp.terminate()
                }

                for _ in 0..<10 {
                    if Task.isCancelled { return false }
                    let current = DockManager.pidsByName("cfprefsd")
                    if oldCfpPIDs.isDisjoint(with: current) { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                for _ in 0..<10 {
                    if Task.isCancelled { return false }
                    let current = DockManager.pidsByName("cfprefsd")
                    if !current.isEmpty && oldCfpPIDs.isDisjoint(with: current) { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                logger.info("Phase 2 attempt \(attempt): cfprefsd restarted")
            }

            // 4. Wait for new Dock
            var newPIDs: Set<pid_t> = []
            for _ in 0..<20 {
                let current = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
                let fresh = Set(current.map { $0.processIdentifier }).subtracting(oldDockPIDs)
                if !fresh.isEmpty { newPIDs = fresh; break }
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return false }
            }

            if newPIDs.isEmpty {
                logger.error("Phase 2 attempt \(attempt): Dock did not restart")
                continue
            }

            logger.info("Phase 2 attempt \(attempt): Dock restarted (new PIDs: \(newPIDs))")

            // 5. Let Dock initialize
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // 6. Verify both plist and cfprefsd
            for readAttempt in 1...4 {
                if Task.isCancelled { return false }

                let plistMatch: Bool = {
                    if let apps = DockManager.readPersistentAppsFromDisk() {
                        return DockManager.parseRawDockData(apps) == set.tiles
                    }
                    return false
                }()

                let cfprefsdMatch: Bool = {
                    if let apps = DockManager.getSystemDockPersistentApps() {
                        return DockManager.parseRawDockData(apps) == set.tiles
                    }
                    return false
                }()

                if !plistMatch {
                    if let apps = DockManager.readPersistentAppsFromDisk() {
                        let tiles = DockManager.parseRawDockData(apps)
                        logger.warning("Read #\(readAttempt) plist: got \(tiles.map(\.label)), expected \(expectedLabels)")
                    }
                }
                if !cfprefsdMatch {
                    if let apps = DockManager.getSystemDockPersistentApps() {
                        let tiles = DockManager.parseRawDockData(apps)
                        logger.warning("Read #\(readAttempt) cfprefsd: got \(tiles.map(\.label)), expected \(expectedLabels)")
                    }
                }

                if plistMatch && cfprefsdMatch {
                    logger.info("First verification passed on read #\(readAttempt)")

                    // Second verification after delay
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if Task.isCancelled { return false }

                    let plistMatch2: Bool = {
                        if let apps = DockManager.readPersistentAppsFromDisk() {
                            return DockManager.parseRawDockData(apps) == set.tiles
                        }
                        return false
                    }()

                    let cfprefsdMatch2: Bool = {
                        if let apps = DockManager.getSystemDockPersistentApps() {
                            return DockManager.parseRawDockData(apps) == set.tiles
                        }
                        return false
                    }()

                    if plistMatch2 && cfprefsdMatch2 {
                        logger.info("Second verification passed (plist + cfprefsd)")
                        return true
                    }

                    if !plistMatch2 {
                        logger.warning("Second verification FAILED: plist mismatch")
                    }
                    if !cfprefsdMatch2 {
                        logger.warning("Second verification FAILED: cfprefsd mismatch")
                    }
                    break
                }

                if readAttempt < 4 {
                    try? await Task.sleep(nanoseconds: UInt64(readAttempt) * 400_000_000)
                }
            }

            logger.error("Phase 2 attempt \(attempt): verification exhausted")
        }

        return false
    }
    
    // MARK: - Core System Logic (Verified Write + Force Kill)

    /// Returns PIDs of processes matching the given name (not bundle ID).
    nonisolated static private func pidsByName(_ name: String) -> Set<pid_t> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var pids = Set<pid_t>()
        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let comm = parts.dropFirst().joined(separator: " ")
            if comm.contains(name), let pid = pid_t(parts[0]) {
                pids.insert(pid)
            }
        }
        return pids
    }

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
    
    /// Full synchronous dock set application (used by manual "Apply" button).
    /// Combines Phase 1 (write plist + cfprefsd) and Phase 2 (restart Dock + verify).
    private func applyDockSetVerified(_ set: DockSet) async -> Bool {
        guard await phase1WriteToDisk(set) else { return false }
        if Task.isCancelled { return false }
        return await phase2RestartDockAndVerify(set)
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

        // Gather metadata matching the Dock's native entry format so the
        // Dock accepts the tile when we write it back.
        let fileModDate: Int
        let parentModDate: Int
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            let ref = Date.timeIntervalSinceReferenceDate
            fileModDate = Int(((attrs[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? ref) * 1_000_000)
            parentModDate = fileModDate
        } else {
            fileModDate = 0
            parentModDate = 0
        }

        let tileData: [String: Any] = [
            "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
            "file-label": name,
            "bundle-identifier": bundleID ?? "",
            "file-type": 41,
            "file-mod-date": fileModDate,
            "parent-mod-date": parentModDate,
            "dock-extra": false,
            "is-beta": false
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

import Foundation
import Combine
import AppKit
import os.log
import Darwin

private actor DockOperationGate {
    private var isLocked = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var waiterOrder: [UUID] = []

    func acquire() async -> Bool {
        guard isLocked else {
            isLocked = true
            return true
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }

                waiters[waiterID] = continuation
                waiterOrder.append(waiterID)
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    func release() {
        while !waiterOrder.isEmpty {
            let waiterID = waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: waiterID) else { continue }
            continuation.resume(returning: true)
            return
        }

        isLocked = false
    }

    private func cancelWaiter(_ waiterID: UUID) {
        guard let continuation = waiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(returning: false)
    }
}

class DockManager: ObservableObject {
    @MainActor @Published var config: DockConfig = DockConfig() {
        didSet {
            saveConfig()
            if config.defaultDockSetID != oldValue.defaultDockSetID {
                lastAppliedDockTiles = nil
            }
        }
    }
    
    @MainActor @Published var activeDockSetID: UUID?
    private var lastAppliedDockTiles: [DockTile]?
    private var dockSwitchGeneration: UInt64 = 0
    
    // Serializes Dock preference and restart operations without blocking a thread
    // while an operation awaits process or Dock state changes.
    private let switchGate = DockOperationGate()

    // Tracks the current switching task
    private var dockTask: Task<Void, Never>?
    
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let configKey = "SpaceSwitcherDockConfig"
    
    // Logger for debugging
    nonisolated private let logger = Logger(subsystem: "dev.mqiu.SpaceSwitcher", category: "DockManager")
    
    init() {
        loadConfig()
        detectActiveDockSet()
    }
    
    /// Scans the system Dock and updates activeDockSetID if a match is found.
    func detectActiveDockSet() {
        let detectionGeneration = dockSwitchGeneration
        Task {
            // Move heavy disk I/O and parsing to a background thread
            let (matchedID, detectedTiles): (UUID?, [DockTile]?) = await Task.detached(priority: .background) {
                guard let rawApps = DockManager.getSystemDockPersistentApps() else { return (nil, nil) }
                let currentTiles = DockManager.parseRawDockData(rawApps)
                
                // We need to access config from MainActor for the comparison
                let matchedID: UUID? = await MainActor.run {
                    if let match = self.config.dockSets.first(where: { $0.tiles == currentTiles }) {
                        return match.id
                    }
                    return nil
                }
                return (matchedID, matchedID == nil ? nil : currentTiles)
            }.value
            
            // Update Published properties on MainActor
            if let id = matchedID, let detectedTiles {
                await MainActor.run {
                    guard self.dockSwitchGeneration == detectionGeneration else { return }
                    self.activeDockSetID = id
                    self.lastAppliedDockTiles = detectedTiles
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

        spaceManager?.$availableSpaces
            .dropFirst()
            .sink { [weak self] spaces in
                self?.migrateManagedSpaceAssignments(using: spaces)
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func migrateManagedSpaceAssignments(using spaces: [SpaceInfo]) {
        var managedToStableIDs: [String: String] = [:]
        for space in spaces {
            if let managedSpaceID = space.managedSpaceID, managedSpaceID != space.id {
                managedToStableIDs[managedSpaceID] = space.id
            }
        }
        guard !managedToStableIDs.isEmpty else { return }

        var updatedAssignments = config.spaceAssignments
        var didUpdate = false
        for (managedSpaceID, dockSetID) in config.spaceAssignments {
            guard let stableSpaceID = managedToStableIDs[managedSpaceID],
                  stableSpaceID != managedSpaceID else {
                continue
            }

            // Keep an already saved stable-ID assignment if both forms exist.
            if updatedAssignments[stableSpaceID] == nil {
                updatedAssignments[stableSpaceID] = dockSetID
            }
            updatedAssignments.removeValue(forKey: managedSpaceID)
            didUpdate = true
        }

        guard didUpdate else { return }
        var updatedConfig = config
        updatedConfig.spaceAssignments = updatedAssignments
        config = updatedConfig
        logger.info("migrated saved dock assignments to DesktopRenamer stable space IDs")
    }
    
    // MARK: - Application Logic

    /// Applies the Dock set for a space after space changes have settled.
    @MainActor
    func applyDockForSpace(_ spaceID: String) {
        dockTask?.cancel()
        dockSwitchGeneration &+= 1
        let requestGeneration = dockSwitchGeneration

        dockTask = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            // Wait for the final space in a rapid sequence before touching
            // Dock preferences or restarting any system processes.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            guard await self.isCurrentDockSwitch(requestGeneration) else { return }

            // Resolve after the debounce so recent assignment edits are used.
            let (targetSet, previouslyAppliedTiles): (DockSet?, [DockTile]?) = await MainActor.run {
                guard self.dockSwitchGeneration == requestGeneration else { return (nil, nil) }
                let setID = self.config.spaceAssignments[spaceID] ?? self.config.defaultDockSetID
                let targetSet = self.config.dockSets.first(where: { $0.id == setID })
                return (targetSet, self.lastAppliedDockTiles)
            }
            guard let set = targetSet else {
                logger.warning("No Dock set configured for space \(spaceID); automatic switch skipped")
                return
            }
            let setName = set.name

            if let currentRaw = DockManager.getSystemDockPersistentApps() {
                let currentTiles = DockManager.parseRawDockData(currentRaw)
                let skipDecision: Bool? = await MainActor.run {
                    guard self.dockSwitchGeneration == requestGeneration else { return nil }
                    guard currentTiles == set.tiles, previouslyAppliedTiles == set.tiles else {
                        return false
                    }
                    if self.activeDockSetID != set.id { self.activeDockSetID = set.id }
                    return true
                }
                guard let shouldSkip = skipDecision else { return }
                if shouldSkip {
                    logger.info("Skipping switch to '\(setName)': Dock preferences match the last verified set")
                    return
                }
                if currentTiles == set.tiles {
                    logger.info("Dock preferences match '\(setName)', but no matching set was verified as applied; continuing with Dock restart")
                }
            }

            let canStartSwitch = await MainActor.run {
                guard self.dockSwitchGeneration == requestGeneration else { return false }
                self.lastAppliedDockTiles = nil
                return true
            }
            guard canStartSwitch else { return }

            logger.info(">>> STARTING SWITCH: '\(setName)' for Space \(spaceID)")
            let success = await self.applyDockSetVerified(set, priority: .utility)

            let isCurrentRequest = await MainActor.run {
                guard self.dockSwitchGeneration == requestGeneration else { return false }
                if success {
                    self.activeDockSetID = set.id
                }
                return true
            }
            guard isCurrentRequest else { return }

            if success {
                logger.info("<<< SUCCESS: Switched to '\(setName)'")
            } else {
                logger.error("<<< FAILURE: Could not verify dock write for '\(setName)'")
            }
        }
    }

    /// Manually applies a specific dock set by its ID.
    /// Uses the full synchronous flow (no debounce).
    @MainActor
    func applyDockSetByID(_ id: UUID) {
        dockTask?.cancel()
        dockSwitchGeneration &+= 1
        let requestGeneration = dockSwitchGeneration
        dockTask = Task {
            guard self.dockSwitchGeneration == requestGeneration else { return }
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated],
                reason: "ManualDockSwitch-\(id)"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }

            guard let set = config.dockSets.first(where: { $0.id == id }) else { return }

            logger.info(">>> MANUAL SWITCH: '\(set.name)'")
            self.lastAppliedDockTiles = nil
            let success = await applyDockSetVerified(set, priority: .userInitiated)
            guard !Task.isCancelled, self.dockSwitchGeneration == requestGeneration else { return }

            if success {
                self.activeDockSetID = set.id
                logger.info("<<< SUCCESS: Manually switched to '\(set.name)'")
            } else {
                logger.error("<<< FAILURE: Could not manually apply Dock set '\(set.name)'")
            }
        }
    }

    private func isCurrentDockSwitch(_ generation: UInt64) async -> Bool {
        await MainActor.run { self.dockSwitchGeneration == generation }
    }

    // MARK: - Dock Switch Transaction

    /// Holds one gate across preference writes, Dock restart, and verification.
    /// Once Dock is asked to quit, the restart runs independently of caller
    /// cancellation so a newer request cannot leave Dock halfway through launch.
    private func applyDockSetVerified(_ set: DockSet, priority: TaskPriority) async -> Bool {
        logger.info("Dock switch '\(set.name)': waiting for operation gate")
        guard await switchGate.acquire() else { return false }
        logger.info("Dock switch '\(set.name)': acquired operation gate")
        guard !Task.isCancelled else {
            await switchGate.release()
            return false
        }

        let phase1Succeeded = await performPhase1WriteToDisk(set)
        guard phase1Succeeded, !Task.isCancelled else {
            await switchGate.release()
            return false
        }

        let restartTask = Task.detached(priority: priority) { [self] in
            await performPhase2RestartDockAndVerify(set)
        }
        let success = await restartTask.value
        if success {
            lastAppliedDockTiles = set.tiles
        }
        await switchGate.release()
        return success
    }

    @concurrent
    private func performPhase1WriteToDisk(_ set: DockSet) async -> Bool {
        guard !Task.isCancelled else { return false }

        logger.info("Phase 1: writing \(set.tiles.count) Dock tiles")
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

        // Update cfprefsd without restarting it. Phase 2 rewrites these
        // preferences after the old Dock has finished its shutdown flush.
        CFPreferencesSetValue(key, newAppData as CFPropertyList, appID,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesAppSynchronize(appID) else {
            logger.error("Phase 1: CFPreferencesAppSynchronize failed")
            return false
        }

        logger.info("Phase 1: wrote \(set.tiles.count) Dock tiles")
        return true
    }

    @concurrent
    private func performPhase2RestartDockAndVerify(_ set: DockSet) async -> Bool {

        if Task.isCancelled { return false }

        let appID = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        let newAppData = DockManager.buildRawDockData(from: set.tiles)
        let expectedLabels = set.tiles.map { $0.label }

        for attempt in 1...3 {
            if Task.isCancelled { return false }

            // 1. Kill Dock — its shutdown will flush stale state to cfprefsd,
            //    overwriting our Phase 1 data. We'll re-write after it's dead.
            let oldDockPIDs = await DockManager.dockProcessIDs()

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
                let currentPIDs = await DockManager.dockProcessIDs()
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
            guard CFPreferencesAppSynchronize(appID) else {
                logger.error("Phase 2 attempt \(attempt): CFPreferencesAppSynchronize failed")
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            logger.info("Phase 2 attempt \(attempt): checking cfprefsd processes")
            let oldCfpPIDs = DockManager.pidsByName("cfprefsd")
            logger.info("Phase 2 attempt \(attempt): found \(oldCfpPIDs.count) cfprefsd processes")
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
                let currentPIDs = await DockManager.dockProcessIDs()
                let fresh = currentPIDs.subtracting(oldDockPIDs)
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

    /// Returns PIDs of processes whose exact process name matches.
    nonisolated static private func pidsByName(_ name: String) -> Set<pid_t> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-u", String(getuid()), "-x", name]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }

        // Drain stdout while pgrep runs so its pipe cannot fill before exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return Set(output
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t(String($0).trimmingCharacters(in: .whitespaces)) })
    }

    nonisolated static private func getSystemDockPersistentApps() -> [Any]? {
        let appID = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString

        guard let apps = CFPreferencesCopyAppValue(key, appID) as? [Any] else {
            return nil
        }
        return apps
    }

    @MainActor
    private static func dockProcessIDs() -> Set<pid_t> {
        Set(NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .map { $0.processIdentifier })
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
    
    // MARK: - Data Management & Spacers
    
    @MainActor
    @discardableResult
    func createNewDockSet(name: String) -> UUID? {
        guard let tiles = currentDockTiles() else { return nil }

        let newSet = DockSet(id: UUID(), name: name, dateCreated: Date(), tiles: tiles)
        config.dockSets.append(newSet)
        if config.defaultDockSetID == nil { config.defaultDockSetID = newSet.id }
        return newSet.id
    }

    /// Replaces a saved dock set with the apps currently pinned in the system Dock.
    /// The current Dock remains unchanged; this only updates the selected configuration.
    @MainActor
    @discardableResult
    func replaceDockItemsWithCurrentDock(for setID: UUID) -> Bool {
        guard let tiles = currentDockTiles(),
              let index = config.dockSets.firstIndex(where: { $0.id == setID }) else {
            return false
        }

        config.dockSets[index].tiles = tiles
        activeDockSetID = setID
        lastAppliedDockTiles = tiles
        return true
    }

    private func currentDockTiles() -> [DockTile]? {
        let rawApps = DockManager.getSystemDockPersistentApps()
            ?? DockManager.readPersistentAppsFromDisk()
        guard let rawApps else { return nil }
        return DockManager.parseRawDockData(rawApps)
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
        let label = NSLocalizedString(isSmall ? "Small spacer" : "Large spacer", comment: "Dock spacer item name")
        
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
                    label = NSLocalizedString("Large spacer", comment: "Dock spacer item name")
                } else if tileType == "small-spacer-tile" {
                    label = NSLocalizedString("Small spacer", comment: "Dock spacer item name")
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

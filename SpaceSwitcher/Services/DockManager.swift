import Foundation
import Combine
import AppKit

class DockManager: ObservableObject {
    @Published var config: DockConfig = DockConfig() {
        didSet {
            saveConfig()
            // Reset cache if default changes so we re-evaluate on next switch
            if config.defaultDockSetID != oldValue.defaultDockSetID {
                lastAppliedDockSetID = nil
            }
        }
    }
    
    private var lastAppliedDockSetID: UUID?
    
    // MARK: - Task Management
    // We use a Task to handle the async nature of waiting (debouncing) and applying settings
    private var dockUpdateTask: Task<Void, Never>?
    
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let configKey = "SpaceSwitcherDockConfig"
    
    init() {
        loadConfig()
    }
    
    private func setupBindings() {
        // Remove .debounce from here and handle it via Task in applyDockForSpace
        // This gives us more granular control over cancellation
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
        // 1. Cancel any pending dock update.
        // If the user is swiping quickly A -> B -> C, we cancel A and B, only applying C.
        dockUpdateTask?.cancel()
        
        dockUpdateTask = Task {
            // 2. DEBOUNCE: Wait for the user to "settle" on this space.
            // 300ms is usually a sweet spot for macOS space switching animations.
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            if Task.isCancelled { return }
            
            // 3. Determine target
            // We do this AFTER the sleep to ensure config is fresh
            await self.performDockSwitch(for: spaceID)
        }
    }
    
    @MainActor
    private func performDockSwitch(for spaceID: String) async {
        let targetSetID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
        
        guard let setID = targetSetID else { return }
        
        // 4. Optimization Check
        // If we are already on this dock set, do nothing.
        // We skip this check if switching to Default to ensure "Reset" behavior works if needed,
        // but generally, if IDs match, the Dock is correct.
        let isSwitchingToDefault = (setID == config.defaultDockSetID)
        if !isSwitchingToDefault && setID == lastAppliedDockSetID {
            print("DOCK: Already on set \(setID), skipping update.")
            return
        }
        
        // 5. Find Data
        guard let set = config.dockSets.first(where: { $0.id == setID }) else { return }
        
        print("DOCK: Applying '\(set.name)' (Delaying for disk write...)")
        
        // 6. Apply with System Safety
        applyDockSet(set)
    }
    
    func createNewDockSet(name: String) {
        guard let rawApps = getSystemDockPersistentApps() else { return }
        let tiles = parseRawDockData(rawApps)
        
        DispatchQueue.main.async {
            let newSet = DockSet(id: UUID(), name: name, dateCreated: Date(), tiles: tiles)
            self.config.dockSets.append(newSet)
            if self.config.defaultDockSetID == nil {
                self.config.defaultDockSetID = newSet.id
            }
        }
    }
    
    // MARK: - System Operations
    
    private func getSystemDockPersistentApps() -> [Any]? {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        return defaults?.array(forKey: "persistent-apps")
    }
    
    private func applyDockSet(_ set: DockSet) {
        let rawData = buildRawDockData(from: set.tiles)
        
        let key = "persistent-apps" as CFString
        let appID = "com.apple.dock" as CFString
        
        // A. Write Preference
        CFPreferencesSetAppValue(key, rawData as CFPropertyList, appID)
        
        // B. Synchronize (Blocking Write)
        let success = CFPreferencesAppSynchronize(appID)
        
        if success {
            // C. CRITICAL: Give the system a moment to flush to disk/cache
            // This prevents the "Race Condition" where Dock restarts before reading new prefs.
            // Since this function is called from an async Task context, we can block briefly
            // without freezing the UI (if we were truly async), but CFPreferences is synchronous.
            // To be safe, we use 'usleep' here as we are on a background Task (conceptually)
            // or we accept a tiny freeze on the main thread (Process launch is heavy anyway).
            usleep(150_000) // 0.15 seconds wait
            
            // D. Restart Dock
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["Dock"]
            task.launch()
            task.waitUntilExit() // Wait for the kill command to finish
            
            // E. Update State
            self.lastAppliedDockSetID = set.id
            print("DOCK: Restarted successfully.")
        } else {
            print("DOCK: Failed to synchronize preferences.")
        }
    }
    
    // MARK: - Helpers
    private func parseRawDockData(_ rawArray: [Any]) -> [DockTile] {
        var tiles: [DockTile] = []
        for case let itemDict as [String: Any] in rawArray {
            guard let tileData = itemDict["tile-data"] as? [String: Any] else { continue }
            let label = tileData["file-label"] as? String ?? "Unknown"
            let bundleID = tileData["bundle-identifier"] as? String
            var url: URL?
            if let urlStr = tileData["file-data"] as? [String: Any], let path = urlStr["_CFURLString"] as? String { url = URL(string: path) }
            tiles.append(DockTile(label: label, bundleIdentifier: bundleID, fileURL: url, rawData: itemDict))
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

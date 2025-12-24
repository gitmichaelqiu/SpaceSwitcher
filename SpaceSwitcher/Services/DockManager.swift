import Foundation
import Combine
import AppKit

class DockManager: ObservableObject {
    @Published var config: DockConfig = DockConfig() {
        didSet { saveConfig() }
    }
    
    // Track current state to avoid infinite loops, but allow re-application
    private var lastAppliedDockSetID: UUID?
    
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let configKey = "SpaceSwitcherDockConfig"
    
    init() {
        loadConfig()
    }
    
    // MARK: - Space Watching
    private func setupBindings() {
        spaceManager?.$currentSpaceID
            .dropFirst().removeDuplicates()
            .sink { [weak self] spaceID in
                guard let self = self, let spaceID = spaceID else { return }
                self.applyDockForSpace(spaceID)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Application Logic
    
    func applyDockForSpace(_ spaceID: String) {
        // 1. Determine Target
        // If space is assigned, use that. Otherwise use default.
        let targetSetID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
        
        // 2. Guard: If no target set exists (e.g. no default set yet), do nothing.
        guard let setID = targetSetID else { return }
        
        // 3. Optimization: Don't re-apply if we are already on this set.
        // EXCEPTION: If we are switching to "Default", we force check because
        // the user might have manually messed with the dock in a non-assigned space.
        if setID == lastAppliedDockSetID && setID != config.defaultDockSetID {
            return
        }
        
        // 4. Retrieve Data
        guard let set = config.dockSets.first(where: { $0.id == setID }) else { return }
        
        // 5. Safety: Don't apply empty docks (prevents accidents)
        guard !set.tiles.isEmpty else {
            print("DOCK: Skipped applying empty set '\(set.name)'")
            return
        }
        
        print("DOCK: Applying set '\(set.name)' for space \(spaceID)...")
        applyDockSet(set)
    }
    
    func createNewDockSet(name: String) {
        // Capture current as a base, or create empty?
        // Usually better to capture current so user doesn't start with blank dock.
        guard let rawApps = getSystemDockPersistentApps() else { return }
        let tiles = parseRawDockData(rawApps)
        
        let newSet = DockSet(id: UUID(), name: name, dateCreated: Date(), tiles: tiles)
        
        DispatchQueue.main.async {
            self.config.dockSets.append(newSet)
            // Auto-set default if it's the first one
            if self.config.defaultDockSetID == nil {
                self.config.defaultDockSetID = newSet.id
            }
        }
    }
    
    // MARK: - System Operations (CFPreferences Fix)
    
    private func getSystemDockPersistentApps() -> [Any]? {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        return defaults?.array(forKey: "persistent-apps")
    }
    
    private func applyDockSet(_ set: DockSet) {
        let rawData = buildRawDockData(from: set.tiles)
        
        // RELIABILITY FIX: Use CoreFoundation Preferences
        // UserDefaults can sometimes cache writes, causing 'killall' to restart with old data.
        // CFPreferencesSetAppValue forces the update to the daemon level.
        let key = "persistent-apps" as CFString
        let appID = "com.apple.dock" as CFString
        
        CFPreferencesSetAppValue(key, rawData as CFPropertyList, appID)
        let success = CFPreferencesAppSynchronize(appID)
        
        if success {
            // Restart Dock
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["Dock"]
            task.launch()
            
            self.lastAppliedDockSetID = set.id
        } else {
            print("DOCK: Failed to synchronize preferences.")
        }
    }
    
    // MARK: - Parsers (Same as before)
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
    
    // MARK: - Persistence
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

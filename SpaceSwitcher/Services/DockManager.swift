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
    
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let configKey = "SpaceSwitcherDockConfig"
    
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
        // 1. Determine target
        let targetSetID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
        
        guard let setID = targetSetID else { return }
        
        // 2. Reliability Check
        let isSwitchingToDefault = (setID == config.defaultDockSetID)
        
        if !isSwitchingToDefault && setID == lastAppliedDockSetID {
            return // Optimization for custom sets
        }
        
        // 3. Find Data
        guard let set = config.dockSets.first(where: { $0.id == setID }) else { return }
        
        // FIX 2: Do NOT return early for empty sets.
        // If the user configured an empty dock, we should apply an empty dock
        // rather than leaving the wrong dock (previous space's dock) active.
        if set.tiles.isEmpty {
            print("DOCK: Applying empty set '\(set.name)' (User configured empty dock)")
            // proceed...
        }
        
        print("DOCK: Applying '\(set.name)' (Default: \(isSwitchingToDefault))")
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
        
        CFPreferencesSetAppValue(key, rawData as CFPropertyList, appID)
        let success = CFPreferencesAppSynchronize(appID)
        
        if success {
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["Dock"]
            task.launch()
            
            self.lastAppliedDockSetID = set.id
        }
    }
    
    // MARK: - Helpers (Same)
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

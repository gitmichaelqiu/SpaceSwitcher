import Foundation
import Combine
import AppKit

class DockManager: ObservableObject {
    @Published var config: DockConfig = DockConfig() {
        didSet { saveConfig() }
    }
    
    private var lastAppliedDockSetID: UUID?
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let configKey = "SpaceSwitcherDockConfig"
    
    init() { loadConfig() }
    
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
    
    // MARK: - Apply Logic
    func applyDockForSpace(_ spaceID: String) {
        let targetSetID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
        guard let setID = targetSetID, setID != lastAppliedDockSetID else { return }
        guard let set = config.dockSets.first(where: { $0.id == setID }) else { return }
        
        print("DOCK: Applying set '\(set.name)'...")
        applyDockSet(set)
    }
    
    // MARK: - Capture Logic
    func captureCurrentDock(as name: String) {
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
    
    // MARK: - Helper: Parse Raw -> [DockTile]
    private func parseRawDockData(_ rawArray: [Any]) -> [DockTile] {
        var tiles: [DockTile] = []
        
        for case let itemDict as [String: Any] in rawArray {
            guard let tileData = itemDict["tile-data"] as? [String: Any] else { continue }
            
            let label = tileData["file-label"] as? String ?? "Unknown"
            let bundleID = tileData["bundle-identifier"] as? String
            
            // Try to extract URL from _CFURLString if available
            var url: URL?
            if let urlStr = tileData["file-data"] as? [String: Any],
               let path = urlStr["_CFURLString"] as? String {
                url = URL(string: path)
            }
            
            // Fallback: If no explicit URL structure, we can sometimes infer it,
            // but usually 'file-data' is a complex dictionary or pure data.
            // For editing purposes, we keep 'rawData' to restore everything we don't understand.
            
            tiles.append(DockTile(label: label, bundleIdentifier: bundleID, fileURL: url, rawData: itemDict))
        }
        return tiles
    }
    
    // MARK: - Helper: [DockTile] -> Raw
    private func buildRawDockData(from tiles: [DockTile]) -> [Any] {
        return tiles.map { $0.rawData }
    }
    
    // MARK: - System Operations
    private func getSystemDockPersistentApps() -> [Any]? {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        return defaults?.array(forKey: "persistent-apps")
    }
    
    private func applyDockSet(_ set: DockSet) {
        let rawData = buildRawDockData(from: set.tiles)
        
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        dockDefaults?.set(rawData, forKey: "persistent-apps")
        dockDefaults?.synchronize()
        
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["Dock"]
        task.launch()
        
        self.lastAppliedDockSetID = set.id
    }
    
    // MARK: - Create Tile from File
    func createTile(from url: URL) -> DockTile {
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = Bundle(url: url)?.bundleIdentifier
        
        // Construct the minimal structure expected by com.apple.dock
        // This is a simplified reconstruction. The Dock usually fills in the details.
        let tileData: [String: Any] = [
            "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
            "file-label": name,
            "bundle-identifier": bundleID ?? "",
            "file-type": 41 // 41 usually denotes an application
        ]
        
        let raw: [String: Any] = [
            "tile-data": tileData,
            "tile-type": "file-tile"
        ]
        
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

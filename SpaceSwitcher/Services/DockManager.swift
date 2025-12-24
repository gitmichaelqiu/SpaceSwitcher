import Foundation
import Combine
import AppKit

class DockManager: ObservableObject {
    @Published var config: DockConfig = DockConfig() {
        didSet { saveConfig() }
    }
    
    // To avoid applying the same dock repeatedly
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
    
    // MARK: - Logic
    
    func applyDockForSpace(_ spaceID: String) {
        // 1. Determine target set
        let targetSetID = config.spaceAssignments[spaceID] ?? config.defaultDockSetID
        
        // 2. Guard against unnecessary updates (Dock restart is jarring)
        guard let setID = targetSetID, setID != lastAppliedDockSetID else { return }
        
        // 3. Find the set data
        guard let set = config.dockSets.first(where: { $0.id == setID }) else { return }
        
        print("DOCK: Applying set '\(set.name)' for space \(spaceID)...")
        applyDockSet(set)
    }
    
    func captureCurrentDock(as name: String) {
        guard let apps = getSystemDockPersistentApps() else { return }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: apps, options: [])
            let newSet = DockSet(id: UUID(), name: name, dateCreated: Date(), persistentAppsData: data)
            
            DispatchQueue.main.async {
                self.config.dockSets.append(newSet)
                // If it's the first one, make it default automatically
                if self.config.defaultDockSetID == nil {
                    self.config.defaultDockSetID = newSet.id
                }
            }
        } catch {
            print("DOCK: Failed to encode dock data: \(error)")
        }
    }
    
    // MARK: - System Operations
    
    private func getSystemDockPersistentApps() -> [Any]? {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        return defaults?.array(forKey: "persistent-apps")
    }
    
    private func applyDockSet(_ set: DockSet) {
        do {
            if let appsArray = try JSONSerialization.jsonObject(with: set.persistentAppsData, options: []) as? [Any] {
                
                // 1. Write to com.apple.dock
                let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
                dockDefaults?.set(appsArray, forKey: "persistent-apps")
                dockDefaults?.synchronize()
                
                // 2. Restart Dock
                let task = Process()
                task.launchPath = "/usr/bin/killall"
                task.arguments = ["Dock"]
                task.launch()
                
                self.lastAppliedDockSetID = set.id
            }
        } catch {
            print("DOCK: Failed to decode dock set for application: \(error)")
        }
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

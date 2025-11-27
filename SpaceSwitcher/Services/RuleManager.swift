import Foundation
import AppKit
import Combine

class RuleManager: ObservableObject {
    @Published var rules: [AppRule] = [] {
        didSet { saveRules() }
    }
    
    weak var spaceManager: SpaceManager? {
        didSet {
            setupBindings()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let rulesKey = "SpaceSwitcherRules"
    
    init() {
        loadRules()
    }
    
    private func setupBindings() {
        spaceManager?.$currentSpaceID
            .dropFirst() // Skip initial load to avoid jarring changes on launch
            .removeDuplicates()
            .sink { [weak self] spaceID in
                guard let self = self, let spaceID = spaceID else { return }
                self.applyRules(for: spaceID)
            }
            .store(in: &cancellables)
    }
    
    private func applyRules(for spaceID: String) {
        for rule in rules where rule.isEnabled {
            let isMatch = rule.targetSpaceIDs.contains(spaceID)
            let actionToPerform = isMatch ? rule.matchAction : rule.elseAction
            
            perform(action: actionToPerform, on: rule.appBundleID)
        }
    }
    
    private func perform(action: WindowAction, on bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        
        switch action {
        case .hide:
            app.hide()
        case .show:
            app.unhide()
            // Optional: Bring to front?
            // app.activate(options: .activateIgnoringOtherApps)
        case .doNothing:
            break
        }
    }
    
    // MARK: - Persistence
    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let decoded = try? JSONDecoder().decode([AppRule].self, from: data) {
            rules = decoded
        }
    }
    
    private func saveRules() {
        if let encoded = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(encoded, forKey: rulesKey)
        }
    }
}

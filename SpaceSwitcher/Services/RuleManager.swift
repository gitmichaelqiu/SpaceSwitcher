import Foundation
import AppKit
import Combine

enum RuleSortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case space = "Space" // Groups by the lowest space number assigned
    
    var id: String { rawValue }
}

class RuleManager: ObservableObject {
    @Published var rules: [AppRule] = [] {
        didSet { saveRules() }
    }
    
    @Published var sortOption: RuleSortOption = .name
    
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
    
    // MARK: - Sorting Logic
    
    var sortedRules: [AppRule] {
        switch sortOption {
        case .name:
            return rules.sorted {
                $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
        case .space:
            return rules.sorted { r1, r2 in
                let s1 = getLowestSpaceNumber(for: r1)
                let s2 = getLowestSpaceNumber(for: r2)
                
                if s1 != s2 {
                    return s1 < s2
                }
                // Secondary sort by name
                return r1.appName.localizedCaseInsensitiveCompare(r2.appName) == .orderedAscending
            }
        }
    }
    
    private func getLowestSpaceNumber(for rule: AppRule) -> Int {
        guard let sm = spaceManager, !rule.targetSpaceIDs.isEmpty else { return 999 }
        
        // Filter available spaces to find matches for this rule
        let matchedSpaces = sm.availableSpaces.filter { rule.targetSpaceIDs.contains($0.id) }
        
        // Return the lowest number found, or 999 if the space ID isn't currently valid/connected
        return matchedSpaces.map { $0.number }.min() ?? 999
    }
    
    // MARK: - Actions
    
    func deleteRule(withID id: UUID) {
        rules.removeAll { $0.id == id }
    }
    
    // MARK: - Rule Execution (Existing)
    
    private func setupBindings() {
        spaceManager?.$currentSpaceID
            .dropFirst()
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

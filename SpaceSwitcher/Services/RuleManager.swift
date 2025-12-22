import Foundation
import AppKit
import Combine
import ApplicationServices

enum RuleSortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case space = "Space"
    
    var id: String { rawValue }
}

class RuleManager: ObservableObject {
    @Published var rules: [AppRule] = [] {
        didSet {
            saveRules()
            refreshRules()
        }
    }
    
    @Published var sortOption: RuleSortOption = .name
    
    weak var spaceManager: SpaceManager? {
        didSet { setupBindings() }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let rulesKey = "SpaceSwitcherRules"
    
    init() {
        loadRules()
    }
    
    // MARK: - Logic & Execution
    
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
    
    /// Helper to manually trigger a refresh based on current state
    private func refreshRules() {
        guard let spaceID = spaceManager?.currentSpaceID else { return }
        // Ensure UI updates happen on main thread if triggered from background
        if Thread.isMainThread {
            self.applyRules(for: spaceID)
        } else {
            DispatchQueue.main.async {
                self.applyRules(for: spaceID)
            }
        }
    }
    
    private func applyRules(for spaceID: String) {
        for rule in rules where rule.isEnabled {
            let isMatch = rule.targetSpaceIDs.contains(spaceID)
            let actionToPerform = isMatch ? rule.matchAction : rule.elseAction
            
            perform(action: actionToPerform, on: rule.appBundleID)
        }
    }
    
    private func perform(action: WindowAction, on bundleID: String) {
        // Find the running app
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        
        switch action {
        case .hide:
            app.hide()
            
        case .show:
            // 1. Unhide (Cmd+H reversal)
            app.unhide()
            // 2. Un-minimize (Cmd+M reversal)
            unminimizeAppWindows(app)
            
        case .minimize:
            minimizeAppWindows(app)
            
        case .doNothing:
            break
        }
    }
    
    // MARK: - Accessibility Helpers
    
    private func minimizeAppWindows(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowsRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        if result == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }
    }
    
    private func unminimizeAppWindows(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowsRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        if result == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                // Check if minimized first
                var isMinimizedRef: AnyObject?
                if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimizedRef) == .success,
                   let isMinimized = isMinimizedRef as? Bool,
                   isMinimized {
                    
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
            }
        }
    }
    
    // MARK: - Sorting & Persistence
    
    var sortedRules: [AppRule] {
        switch sortOption {
        case .name:
            return rules.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        case .space:
            return rules.sorted { r1, r2 in
                let s1 = getLowestSpaceNumber(for: r1)
                let s2 = getLowestSpaceNumber(for: r2)
                return s1 != s2 ? s1 < s2 : r1.appName.localizedCaseInsensitiveCompare(r2.appName) == .orderedAscending
            }
        }
    }
    
    private func getLowestSpaceNumber(for rule: AppRule) -> Int {
        guard let sm = spaceManager, !rule.targetSpaceIDs.isEmpty else { return 999 }
        let matchedSpaces = sm.availableSpaces.filter { rule.targetSpaceIDs.contains($0.id) }
        return matchedSpaces.map { $0.number }.min() ?? 999
    }
    
    func deleteRule(withID id: UUID) {
        rules.removeAll { $0.id == id }
    }
    
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

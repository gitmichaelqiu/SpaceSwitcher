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
    
    private func refreshRules() {
        guard let spaceID = spaceManager?.currentSpaceID else { return }
        if Thread.isMainThread {
            self.applyRules(for: spaceID)
        } else {
            DispatchQueue.main.async { self.applyRules(for: spaceID) }
        }
    }
    
    private func applyRules(for spaceID: String) {
        for rule in rules where rule.isEnabled {
            let isMatch = rule.targetSpaceIDs.contains(spaceID)
            let actions = isMatch ? rule.matchActions : rule.elseActions
            perform(actions: actions, on: rule.appBundleID)
        }
    }
    
    private func perform(actions: [WindowAction], on bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        
        for action in actions {
            switch action {
            case .hide:
                app.hide()
                
            case .show:
                // FIX: Use AX to unhide without activating (preserves layer)
                unhideAppWithoutActivation(app)
                // Also ensure individual windows are not minimized
                unminimizeAppWindows(app)
                
            case .minimize:
                minimizeAppWindows(app)
                
            case .bringToFront:
                app.activate(options: .activateIgnoringOtherApps)
            }
        }
    }
    
    // MARK: - Accessibility Helpers
    
    private func unhideAppWithoutActivation(_ app: NSRunningApplication) {
        // If we use app.unhide(), it activates the app.
        // Instead, we set kAXHiddenAttribute to false via Accessibility.
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, kCFBooleanFalse)
    }
    
    private func minimizeAppWindows(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }
    }
    
    private func unminimizeAppWindows(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        // Note: Getting windows often only returns visible ones, but unhiding the app first helps.
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                var isMin: AnyObject?
                if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMin) == .success,
                   let minBool = isMin as? Bool, minBool {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
            }
        }
    }
    
    // MARK: - Sorting & Persistence
    // (Existing code: sortedRules, getLowestSpaceNumber, deleteRule, loadRules, saveRules...)
    var sortedRules: [AppRule] {
        switch sortOption {
        case .name: return rules.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
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
    
    func deleteRule(withID id: UUID) { rules.removeAll { $0.id == id } }
    
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

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
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let rulesKey = "SpaceSwitcherRules"
    
    init() { loadRules() }
    
    private func setupBindings() {
        spaceManager?.$currentSpaceID
            .dropFirst().removeDuplicates()
            .sink { [weak self] spaceID in
                guard let self = self, let spaceID = spaceID else { return }
                self.applyRules(for: spaceID)
            }
            .store(in: &cancellables)
    }
    
    private func refreshRules() {
        guard let spaceID = spaceManager?.currentSpaceID else { return }
        if Thread.isMainThread { self.applyRules(for: spaceID) }
        else { DispatchQueue.main.async { self.applyRules(for: spaceID) } }
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
        
        // Execute sequentially
        // Note: For hotkeys, we might need a tiny delay if the previous action was "Show"
        Task { @MainActor in
            for action in actions {
                switch action {
                case .hide:
                    app.hide()
                    
                case .show:
                    unhideAppWithoutActivation(app)
                    unminimizeAppWindows(app)
                    
                case .minimize:
                    minimizeAppWindows(app)
                    
                case .bringToFront:
                    app.activate(options: .activateIgnoringOtherApps)
                    
                case .hotkey(let keyCode, let modifiers):
                    // Ensure app is frontmost before typing
                    // (Unless the user wants global shortcuts, but usually it's for the target app)
                    if !app.isActive {
                        app.activate(options: .activateIgnoringOtherApps)
                        // Give it a moment to take focus
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    }
                    simulateHotkey(keyCode: keyCode, modifiers: modifiers)
                }
            }
        }
    }
    
    private func simulateHotkey(keyCode: Int, modifiers: UInt) {
        guard keyCode >= 0 else { return }
        
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        
        // Create Key Down
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) else { return }
        keyDown.flags = flags
        keyDown.post(tap: .cghidEventTap)
        
        // Create Key Up
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }
        keyUp.flags = flags
        keyUp.post(tap: .cghidEventTap)
    }
    
    // ... (Accessibility helpers: unhideAppWithoutActivation, minimizeAppWindows, unminimizeAppWindows, Sorting, Persistence - SAME AS BEFORE) ...
    // Keeping them omitted for brevity as they haven't changed since previous step
    
    // (Include the rest of the file from the previous step here)
    private func unhideAppWithoutActivation(_ app: NSRunningApplication) {
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

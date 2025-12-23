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
    
    func forceRefresh() {
        guard let spaceID = spaceManager?.currentSpaceID else { return }
        if Thread.isMainThread { self.applyRules(for: spaceID) }
        else { DispatchQueue.main.async { self.applyRules(for: spaceID) } }
    }
    
    private func applyRules(for spaceID: String) {
        for rule in rules where rule.isEnabled {
            // 1. Check Groups
            if let matchingGroup = rule.groups.first(where: { $0.targetSpaceIDs.contains(spaceID) }) {
                perform(actions: matchingGroup.actions, on: rule.appBundleID)
            } else {
                // 2. Fallback
                perform(actions: rule.elseActions, on: rule.appBundleID)
            }
        }
    }
    
    private func perform(actions: [ActionItem], on bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        
        Task { @MainActor in
            for item in actions {
                switch item.value {
                case .hide:
                    app.hide()
                    
                case .show:
                    let wasHidden = app.isHidden
                    unhideAppWithoutActivation(app)
                    unminimizeAppWindows(app)
                    // If app was hidden, give it a moment to appear before processing next actions
                    if wasHidden {
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                    }
                    
                case .minimize:
                    minimizeAppWindows(app)
                    
                case .bringToFront:
                    app.activate(options: .activateIgnoringOtherApps)
                    
                case .hotkey(let k, let m):
                    // ROBUST HOTKEY EXECUTION
                    
                    // 1. Ensure App is Active
                    if !app.isActive {
                        app.activate(options: .activateIgnoringOtherApps)
                        
                        // 2. Poll until it is actually active (Max 1.0s)
                        var retries = 0
                        while !app.isActive && retries < 20 {
                            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s poll
                            retries += 1
                        }
                        
                        // 3. Animation Buffer: Wait for "unminimize/zoom" animation to finish
                        // Even if .isActive is true, the window might still be flying in.
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    } else {
                        // Even if already active, add a tiny buffer to ensure the event loop isn't busy
                        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                    }
                    
                    // 4. Fire
                    simulateHotkey(keyCode: k, modifiers: m)
                }
            }
        }
    }
    
    private func simulateHotkey(keyCode: Int, modifiers: UInt) {
        guard keyCode >= 0 else { return }
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) else { return }
        keyDown.flags = flags
        keyDown.post(tap: .cghidEventTap)
        
        // Tiny delay between Down and Up to register correctly
        usleep(10000) // 0.01s
        
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }
        keyUp.flags = flags
        keyUp.post(tap: .cghidEventTap)
    }

    private func getLowestSpaceNumber(for rule: AppRule) -> Int {
        guard let sm = spaceManager else { return 999 }
        let allIDs = rule.groups.flatMap { $0.targetSpaceIDs }
        if allIDs.isEmpty { return 999 }
        
        let matched = sm.availableSpaces.filter { allIDs.contains($0.id) }
        return matched.map { $0.number }.min() ?? 999
    }
    
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

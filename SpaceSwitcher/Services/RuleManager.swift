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
    @Published var rules: [AppRule] = [] { didSet { saveRules() } }
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
            if let matchingGroup = rule.groups.first(where: { $0.targetSpaceIDs.contains(spaceID) }) {
                perform(actions: matchingGroup.actions, on: rule.appBundleID)
            } else {
                perform(actions: rule.elseActions, on: rule.appBundleID)
            }
        }
    }
    
    private func perform(actions: [ActionItem], on bundleID: String) {
        // NOTE: Even for Global Hotkeys, we check bundleID existence loosely,
        // but Global Hotkeys technically don't require the app to be running.
        // However, the rule structure is tied to an app.
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        
        let previousApp = NSWorkspace.shared.frontmostApplication
        
        Task { @MainActor in
            for item in actions {
                switch item.value {
                case .hide: app.hide()
                case .show:
                    let wasHidden = app.isHidden
                    unhideAppWithoutActivation(app)
                    unminimizeAppWindows(app)
                    if wasHidden { try? await Task.sleep(nanoseconds: 200_000_000) }
                    
                case .minimize: minimizeAppWindows(app)
                case .bringToFront: app.activate(options: .activateIgnoringOtherApps)
                    
                // --- NEW: Global Hotkey ---
                case .globalHotkey(let k, let m):
                    // No activation logic. Just fire.
                    simulateHotkey(keyCode: k, modifiers: m)
                    
                // --- Standard Hotkey ---
                case .hotkey(let k, let m, let restoreWindow, let waitFrontmost):
                    if waitFrontmost {
                        // MODE A: WAIT (Passive)
                        var retries = 0
                        while !app.isActive && retries < 100 {
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            retries += 1
                        }
                        if !app.isActive { continue }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        
                    } else {
                        // MODE B: FORCE (Aggressive)
                        // Retry activation loop to handle stubborn apps
                        var attempts = 0
                        while !app.isActive && attempts < 5 {
                            app.activate(options: .activateIgnoringOtherApps)
                            
                            // Check if successful
                            var check = 0
                            while !app.isActive && check < 5 { // Wait up to 0.25s per attempt
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                check += 1
                            }
                            attempts += 1
                        }
                        
                        // Final animation buffer
                        if app.isActive {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }
                    }
                    
                    simulateHotkey(keyCode: k, modifiers: m)
                    
                    if !waitFrontmost && restoreWindow, let prev = previousApp, prev.processIdentifier != app.processIdentifier {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        prev.activate(options: .activateIgnoringOtherApps)
                    }
                }
            }
        }
    }
    
    private func simulateHotkey(keyCode: Int, modifiers: UInt) {
        guard keyCode >= 0 else { return }
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        guard let d = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) else { return }
        d.flags = flags; d.post(tap: .cghidEventTap)
        usleep(10000)
        guard let u = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }
        u.flags = flags; u.post(tap: .cghidEventTap)
    }

    // ... (Helpers: getLowestSpaceNumber, unhideAppWithoutActivation, etc. remain unchanged) ...
    private func getLowestSpaceNumber(for rule: AppRule) -> Int {
        guard let sm = spaceManager else { return 999 }
        let allIDs = rule.groups.flatMap { $0.targetSpaceIDs }
        if allIDs.isEmpty { return 999 }
        let matched = sm.availableSpaces.filter { allIDs.contains($0.id) }
        return matched.map { $0.number }.min() ?? 999
    }
    private func unhideAppWithoutActivation(_ app: NSRunningApplication) {
         let pid = app.processIdentifier; let appElement = AXUIElementCreateApplication(pid)
         AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, kCFBooleanFalse)
    }
    private func minimizeAppWindows(_ app: NSRunningApplication) {
        let pid = app.processIdentifier; let appElement = AXUIElementCreateApplication(pid); var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
        }
    }
    private func unminimizeAppWindows(_ app: NSRunningApplication) {
        let pid = app.processIdentifier; let appElement = AXUIElementCreateApplication(pid); var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows { var isMin: AnyObject?; if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMin) == .success, let minBool = isMin as? Bool, minBool { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) } }
        }
    }
    
    var sortedRules: [AppRule] {
        switch sortOption {
        case .name: return rules.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        case .space: return rules.sorted { r1, r2 in let s1 = getLowestSpaceNumber(for: r1); let s2 = getLowestSpaceNumber(for: r2); return s1 != s2 ? s1 < s2 : r1.appName.localizedCaseInsensitiveCompare(r2.appName) == .orderedAscending }
        }
    }
    func deleteRule(withID id: UUID) { rules.removeAll { $0.id == id } }
    private func loadRules() { if let data = UserDefaults.standard.data(forKey: rulesKey), let decoded = try? JSONDecoder().decode([AppRule].self, from: data) { rules = decoded } }
    private func saveRules() { if let encoded = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(encoded, forKey: rulesKey) } }
}

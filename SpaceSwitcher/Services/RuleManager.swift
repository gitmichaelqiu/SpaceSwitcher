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
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        
        // Capture currently active app for the "Restore Active Window" feature
        let previousApp = NSWorkspace.shared.frontmostApplication
        
        Task { @MainActor in
            for item in actions {
                switch item.value {
                case .hide:
                    app.hide()
                    
                case .show:
                    let wasHidden = app.isHidden
                    unhideAppWithoutActivation(app)
                    unminimizeAppWindows(app)
                    if wasHidden { try? await Task.sleep(nanoseconds: 200_000_000) }
                    
                case .minimize:
                    minimizeAppWindows(app)
                    
                case .bringToFront:
                    app.activate(options: .activateIgnoringOtherApps)
                    
                case .hotkey(let k, let m, let restoreWindow, let waitFrontmost):
                    // 1. Activate Target
                    if !app.isActive {
                        app.activate(options: .activateIgnoringOtherApps)
                        
                        // 2. Wait logic
                        if waitFrontmost {
                            var retries = 0
                            while !app.isActive && retries < 20 {
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                retries += 1
                            }
                            // Animation buffer
                            try? await Task.sleep(nanoseconds: 300_000_000)
                        }
                    } else {
                        // Small buffer for event loop
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                    
                    // 3. Fire Hotkey
                    simulateHotkey(keyCode: k, modifiers: m)
                    
                    // 4. Restore Previous App if requested
                    if restoreWindow, let prev = previousApp, prev.processIdentifier != app.processIdentifier {
                        // Small delay to ensure hotkey registers before switching away
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
        
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) else { return }
        keyDown.flags = flags
        keyDown.post(tap: .cghidEventTap)
        
        usleep(10000)
        
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
    
    // Accessibility Helpers
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

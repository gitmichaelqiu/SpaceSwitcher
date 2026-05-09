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
    @Published var isAutomationEnabled: Bool = true { didSet { UserDefaults.standard.set(isAutomationEnabled, forKey: "isAutomationEnabled") ; saveRules() } }
    @Published var sortOption: RuleSortOption = .name
    weak var spaceManager: SpaceManager? { didSet { setupBindings() } }
    private var cancellables = Set<AnyCancellable>()
    private let rulesKey = "SpaceSwitcherRules"
    
    // TRACKING: Managed visibility states
    private var managedHides = Set<String>()
    private var managedMinimizes = Set<String>()
    
    // MASTER TASK: Tracks the current rule enforcement process
    private var enforcementTask: Task<Void, Never>?
    
    init() { 
        self.isAutomationEnabled = UserDefaults.standard.object(forKey: "isAutomationEnabled") as? Bool ?? true
        loadRules() 
    }
    
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
        // Always run on main thread via the Task manager
        self.applyRules(for: spaceID)
    }
    
    private func applyRules(for spaceID: String) {
        // 1. Cancel any existing enforcement (Fixes the "Stale Action" bug)
        enforcementTask?.cancel()
        
        // 2. Start new enforcement task
        enforcementTask = Task {
            guard isAutomationEnabled else { return }
            
            for rule in rules where rule.isEnabled {
                // Check cancellation before every rule
                if Task.isCancelled { return }
                
                if let matchingGroup = rule.groups.first(where: { $0.targetSpaceIDs.contains(spaceID) }) {
                    await perform(actions: matchingGroup.actions, on: rule.appBundleID)
                } else {
                    await perform(actions: rule.elseActions, on: rule.appBundleID)
                }
            }
        }
    }
    
    // UPDATED: Now an async function called by the Master Task (No internal Task creation)
    private func perform(actions: [ActionItem], on bundleID: String) async {
        // Loosely check app existence
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        
        let previousApp = NSWorkspace.shared.frontmostApplication
        
        for item in actions {
            // Check cancellation before every action
            if Task.isCancelled { return }
            
            switch item.value {
            case .hide:
                if !isAppEffectivelyHidden(app) {
                    managedHides.insert(bundleID)
                }
                app.hide()
                
            case .show:
                managedHides.remove(bundleID)
                managedMinimizes.remove(bundleID)
                let wasHidden = app.isHidden
                unhideAppWithoutActivation(app)
                unminimizeAppWindows(app)
                if wasHidden { try? await Task.sleep(nanoseconds: 200_000_000) }

            case .restore:
                let shouldUnhide = managedHides.contains(bundleID)
                let shouldUnminimize = managedMinimizes.contains(bundleID)
                managedHides.remove(bundleID)
                managedMinimizes.remove(bundleID)
                
                if shouldUnhide {
                    unhideAppWithoutActivation(app)
                }
                if shouldUnminimize {
                    unminimizeAppWindows(app)
                }
                if shouldUnhide { try? await Task.sleep(nanoseconds: 200_000_000) }
                
            case .minimize:
                if !isAppEffectivelyHidden(app) {
                    if minimizeAppWindows(app) {
                        managedMinimizes.insert(bundleID)
                    }
                } else {
                    // Even if already hidden/minimized, we still run the minimize command 
                    // to ensure consistency, but we don't 'claim' it as managed.
                    minimizeAppWindows(app)
                }
                
            case .bringToFront:
                app.activate(options: .activateIgnoringOtherApps)
                
            case .globalHotkey(let k, let m):
                simulateHotkey(keyCode: k, modifiers: m)
                
            case .hotkey(let k, let m, let restoreWindow, let waitFrontmost):
                
                if waitFrontmost {
                    // MODE A: WAIT
                    var retries = 0
                    // Poll for 5 seconds
                    while !app.isActive && retries < 100 {
                        if Task.isCancelled { return } // Stop if space changed
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        retries += 1
                    }
                    
                    if !app.isActive { continue } // Timed out or cancelled
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    
                } else {
                    // MODE B: FORCE
                    var attempts = 0
                    while !app.isActive && attempts < 5 {
                        if Task.isCancelled { return }
                        app.activate(options: .activateIgnoringOtherApps)
                        
                        var check = 0
                        while !app.isActive && check < 5 {
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            check += 1
                        }
                        attempts += 1
                    }
                    
                    if app.isActive {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                
                // Final check before firing keys
                if Task.isCancelled { return }
                simulateHotkey(keyCode: k, modifiers: m)
                
                if !waitFrontmost && restoreWindow, let prev = previousApp, prev.processIdentifier != app.processIdentifier {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if !Task.isCancelled {
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

    // ... (Helpers remain unchanged) ...
    private func getLowestSpaceNumber(for rule: AppRule) -> Int {
        guard let sm = spaceManager else { return 999 }
        let allIDs = rule.groups.flatMap { $0.targetSpaceIDs }
        if allIDs.isEmpty { return 999 }
        let matched = sm.availableSpaces.filter { allIDs.contains($0.id) }
        return matched.map { $0.number }.min() ?? 999
    }
    private func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func isAppEffectivelyHidden(_ app: NSRunningApplication) -> Bool {
        if app.isHidden { return true }
        
        // If not hidden, check if all windows are minimized
        if !checkAccessibility() { return false }
        let pid = app.processIdentifier; let appElement = AXUIElementCreateApplication(pid); var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success, let windows = windowsRef as? [AXUIElement] {
            if windows.isEmpty { return false }
            for window in windows { 
                var isMin: AnyObject?
                if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMin) == .success, let minBool = isMin as? Bool {
                    if !minBool { return false } // Found a visible window
                } else {
                    return false // Could not determine, assume visible
                }
            }
            return true // All windows are minimized
        }
        return false
    }
    
    private func unhideAppWithoutActivation(_ app: NSRunningApplication) {
        if !checkAccessibility() { print("RULE: Accessibility permission missing, skipping unhide") ; return }
        let pid = app.processIdentifier; let appElement = AXUIElementCreateApplication(pid)
        let result = AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, kCFBooleanFalse)
        if result != .success { print("RULE: Failed to unhide \(app.localizedName ?? "Unknown"): \(result.rawValue)") }
    }
    @discardableResult
    private func minimizeAppWindows(_ app: NSRunningApplication) -> Bool {
        if !checkAccessibility() { print("RULE: Accessibility permission missing, skipping minimize") ; return false }
        let pid = app.processIdentifier; let appElement = AXUIElementCreateApplication(pid); var windowsRef: AnyObject?
        var didMinimizeSomething = false
        
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows { 
                var isMin: AnyObject?
                if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMin) == .success, let minBool = isMin as? Bool {
                    if !minBool {
                        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                        if result == .success {
                            didMinimizeSomething = true
                        } else {
                            print("RULE: Failed to minimize window: \(result.rawValue)")
                        }
                    }
                }
            }
        }
        return didMinimizeSomething
    }
    private func unminimizeAppWindows(_ app: NSRunningApplication) {
        if !checkAccessibility() { print("RULE: Accessibility permission missing, skipping unminimize") ; return }
        let pid = app.processIdentifier; let appElement = AXUIElementCreateApplication(pid); var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows { 
                var isMin: AnyObject?
                if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMin) == .success, let minBool = isMin as? Bool, minBool { 
                    let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) 
                    if result != .success { print("RULE: Failed to unminimize window: \(result.rawValue)") }
                } 
            }
        }
    }
    var sortedRules: [AppRule] {
        switch sortOption {
        case .name: return rules.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        case .space: return rules.sorted { r1, r2 in let s1 = getLowestSpaceNumber(for: r1); let s2 = getLowestSpaceNumber(for: r2); return s1 != s2 ? s1 < s2 : r1.appName.localizedCaseInsensitiveCompare(r2.appName) == .orderedAscending }
        }
    }
    func addRule(_ rule: AppRule) {
        rules.append(rule)
    }
    
    func updateRule(_ rule: AppRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        }
    }
    
    func deleteRule(_ rule: AppRule) {
        rules.removeAll { $0.id == rule.id }
    }
    
    func deleteRule(withID id: UUID) { rules.removeAll { $0.id == id } }
    private func loadRules() { if let data = UserDefaults.standard.data(forKey: rulesKey), let decoded = try? JSONDecoder().decode([AppRule].self, from: data) { rules = decoded } }
    private func saveRules() { if let encoded = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(encoded, forKey: rulesKey) } }
}

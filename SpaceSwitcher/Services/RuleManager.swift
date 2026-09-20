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
            forceRefresh()
        }
    }
    @Published var isAutomationEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isAutomationEnabled, forKey: "isAutomationEnabled")
            if isAutomationEnabled {
                forceRefresh()
            } else {
                enforcementTask?.cancel()
            }
        }
    }
    @Published var sortOption: RuleSortOption = .name
    weak var spaceManager: SpaceManager? {
        didSet {
            setupBindings()
            forceRefresh()
        }
    }
    private var cancellables = Set<AnyCancellable>()
    private let rulesKey = "SpaceSwitcherRules"
    
    // Managed visibility states are keyed by WindowServer window ID so a rule
    // can restore only the windows it changed. App-level fallbacks are keyed by
    // process ID when an application does not expose an AX window list.
    // Keep the last AX target as well as its ID. macOS can temporarily omit a
    // hidden window from kAXWindowsAttribute after we hide it. Retaining the
    // target lets a source-space pass restore it once the user returns.
    private var managedHides: [Int: RuleWindowTarget] = [:]
    private var managedMinimizes = Set<Int>()
    // Keep the source spaces for application-level hides. macOS can remove
    // all of a hidden application's AX windows, so the source-space trigger
    // must remain available even when the next evaluation has no windows.
    private var managedAppHides: [Int32: Set<String>] = [:]
    private var managedAppMinimizes = Set<Int32>()
    
    // Tracks the current rule enforcement process
    private var enforcementTask: Task<Void, Never>?
    
    init() { 
        loadRules() 
        self.isAutomationEnabled = UserDefaults.standard.object(forKey: "isAutomationEnabled") as? Bool ?? true
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        print("[SpaceSwitcher][Rules] \(message())")
    }
    
    private func setupBindings() {
        spaceManager?.$currentSpaceID
            .dropFirst().removeDuplicates()
            .sink { [weak self] spaceID in
                guard let self = self, let spaceID = spaceID else { return }
                self.debugLog("space change received: current=\(spaceID), settling=150ms")
                // SpaceAPI can publish the new desktop before WindowServer and
                // Accessibility have finished updating window membership.
                self.applyRules(for: spaceID, settlingDelay: 150_000_000)
            }
            .store(in: &cancellables)
    }
    
    func forceRefresh() {
        guard let spaceID = spaceManager?.currentSpaceID else { return }
        debugLog("force refresh: current=\(spaceID)")
        // Always run on main thread via the Task manager
        self.applyRules(for: spaceID)
    }

    private func applyRules(for spaceID: String, settlingDelay: UInt64 = 0) {
        debugLog("apply start: space=\(spaceID), delay=\(settlingDelay / 1_000_000)ms, enabled=\(isAutomationEnabled)")
        // Cancel existing enforcement to prevent stale actions
        enforcementTask?.cancel()
        
        // Start new enforcement task
        enforcementTask = Task { [weak self] in
            guard let self else { return }
            guard isAutomationEnabled else {
                self.debugLog("apply skipped: automation disabled")
                return
            }

            if settlingDelay > 0 {
                try? await Task.sleep(nanoseconds: settlingDelay)
                guard !Task.isCancelled,
                      self.spaceManager?.currentSpaceID == spaceID else {
                    self.debugLog("apply cancelled after settling: requested=\(spaceID), current=\(self.spaceManager?.currentSpaceID ?? "nil")")
                    return
                }
            }
            
            for rule in rules where rule.isEnabled {
                // Check cancellation before every rule
                if Task.isCancelled { return }

                let applications = applications(for: rule)
                self.debugLog("rule \(rule.id.uuidString.prefix(8)) app=\(rule.appName.isEmpty ? "<all>" : rule.appName) applications=\(applications.count)")
                var didPerformGlobalHotkey = false

                for application in applications {
                    if Task.isCancelled { return }

                    var allWindows = WindowSpaceService.windows(for: application)
                    self.debugLog("app \(application.localizedName ?? "<unknown>") pid=\(application.processIdentifier) hidden=\(application.isHidden) active=\(application.isActive) AXWindows=\(allWindows.count) managedAppHideSources=\(self.managedAppHides[application.processIdentifier]?.sorted().joined(separator: ",") ?? "none")")
                    for window in allWindows {
                        self.debugLog(self.windowDebugSummary(window, prefix: "  AX window"))
                    }
                    let knownWindowIDs = Set(allWindows.map(\.id))

                    // A hidden AX window may disappear from the application's
                    // window list. Merge back targets that this rule changed
                    // so a Restore action can still match its source space.
                    allWindows.append(contentsOf: managedHides.values.filter {
                        $0.applicationPID == application.processIdentifier
                            && !knownWindowIDs.contains($0.id)
                    })
                    if allWindows.count != knownWindowIDs.count {
                        self.debugLog("app \(application.localizedName ?? "<unknown>") merged managed windows: total=\(allWindows.count)")
                    }
                    let plans: [RuleWindowPlan]

                    if allWindows.isEmpty {
                        // A source-space or window-state condition cannot be
                        // evaluated without an accessibility window list.
                        // Preserve ordinary app-level actions, but never guess
                        // a window condition.
                        let sourceSpaceIDs = managedAppHides[application.processIdentifier] ?? []
                        let rawActions = rule.groups.first(where: { group in
                            (!group.usesSourceSpace && group.targetSpaceIDs.contains(spaceID))
                                || (group.usesSourceSpace && sourceSpaceIDs.contains(spaceID))
                        })?.actions ?? rule.elseActions
                        let actions = evaluatedActions(
                            rawActions,
                            context: RuleEvaluationContext(window: nil)
                        )
                        self.debugLog("app \(application.localizedName ?? "<unknown>") has no AX windows; raw=\(self.actionDebugSummary(rawActions.map(\.value))) evaluated=\(self.actionDebugSummary(actions))")
                        plans = actions.isEmpty
                            ? []
                            : [RuleWindowPlan(actions: actions, windows: [])]
                    } else {
                        plans = windowPlans(
                            for: rule,
                            currentSpaceID: spaceID,
                            windows: allWindows,
                            application: application
                        )
                    }

                    self.debugLog("app \(application.localizedName ?? "<unknown>") plans=\(plans.count)")
                    for plan in plans {
                        self.debugLog("  plan actions=\(self.actionDebugSummary(plan.actions)) windows=[\(plan.windows.map { String($0.id) }.joined(separator: ","))]")
                    }

                    for plan in plans {
                        if Task.isCancelled { return }

                        let hasGlobalHotkey = plan.actions.contains {
                            if case .globalHotkey = $0 { return true }
                            return false
                        }

                        await perform(
                            actions: plan.actions,
                            on: application,
                            allWindows: allWindows,
                            targetWindows: plan.windows,
                            performGlobalHotkeys: hasGlobalHotkey && !didPerformGlobalHotkey
                        )

                        if hasGlobalHotkey {
                            didPerformGlobalHotkey = true
                        }
                    }
                }
            }
        }
    }

    private func windowDebugSummary(_ window: RuleWindowTarget, prefix: String = "window") -> String {
        let liveMinimized = WindowSpaceService.isMinimized(window)
        let liveHidden = WindowSpaceService.isHidden(window)
        return "\(prefix) id=\(window.id) spaces=[\(window.spaceIDs.sorted().joined(separator: ","))] minimized(snapshot=\(boolDebug(window.isMinimized)),live=\(boolDebug(liveMinimized))) hidden(snapshot=\(boolDebug(window.isHidden)),live=\(boolDebug(liveHidden))) frontmost=\(window.isFrontmost)"
    }

    private func boolDebug(_ value: Bool?) -> String {
        value.map(String.init) ?? "unknown"
    }

    private func actionDebugSummary(_ actions: [WindowAction]) -> String {
        actions.map { action in
            switch action {
            case .ifCondition(let condition): return "if(\(condition.rawValue))"
            case .endIf: return "endIf"
            default: return action.localizedString
            }
        }.joined(separator: " -> ")
    }

    private struct RuleWindowPlan {
        let actions: [WindowAction]
        var windows: [RuleWindowTarget]
    }

    private struct RuleEvaluationContext {
        let window: RuleWindowTarget?
    }

    private func windowPlans(
        for rule: AppRule,
        currentSpaceID: String,
        windows: [RuleWindowTarget],
        application: NSRunningApplication
    ) -> [RuleWindowPlan] {
        var plans: [RuleWindowPlan] = []

        for window in windows {
            let matchingGroup = rule.groups.first { group in
                let spaceMatches = group.targetSpaceIDs.contains(currentSpaceID)
                    || (group.usesSourceSpace && window.spaceIDs.contains(currentSpaceID))

                return spaceMatches
            }
            let rawActions = matchingGroup?.actions ?? rule.elseActions
            let actions = evaluatedActions(
                rawActions,
                context: RuleEvaluationContext(window: window)
            )
            debugLog("match app=\(application.localizedName ?? "<unknown>") window=\(window.id) currentSpace=\(currentSpaceID) group=\(matchingGroup?.id.uuidString.prefix(8).description ?? "fallback") raw=\(actionDebugSummary(rawActions.map(\.value))) evaluated=\(actionDebugSummary(actions))")

            guard !actions.isEmpty else { continue }

            if let index = plans.firstIndex(where: { $0.actions == actions }) {
                plans[index].windows.append(window)
            } else {
                plans.append(RuleWindowPlan(actions: actions, windows: [window]))
            }
        }

        return plans
    }

    private func evaluatedActions(
        _ items: [ActionItem],
        context: RuleEvaluationContext
    ) -> [WindowAction] {
        var result: [WindowAction] = []
        var activeConditionResult: Bool?

        for item in items {
            switch item.value {
            case .ifCondition(let condition):
                // Conditional blocks are intentionally flat. Treat malformed
                // nested blocks as false until their matching End If rather
                // than accidentally executing actions.
                if activeConditionResult != nil {
                    activeConditionResult = false
                } else {
                    activeConditionResult = conditionMatches(condition, context: context)
                }
            case .endIf:
                activeConditionResult = nil
            default:
                if activeConditionResult != false {
                    result.append(item.value)
                }
            }
        }

        return result
    }

    private func conditionMatches(
        _ condition: RuleCondition,
        context: RuleEvaluationContext
    ) -> Bool {
        switch condition {
        case .windowMinimized:
            guard let window = context.window else { return false }
            return (WindowSpaceService.isMinimized(window) ?? window.isMinimized) == true
        case .windowFrontmost:
            return context.window?.isFrontmost == true
        case .windowHidden:
            return context.window?.isHidden == true
        case .windowFullscreen:
            return context.window?.isFullscreen == true
        }
    }
    
    private func applications(for rule: AppRule) -> [NSRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        if rule.appliesToAllApps {
            return NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && $0.processIdentifier != ownPID
            }
        }

        guard !rule.appBundleID.isEmpty else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: rule.appBundleID)
            .filter { $0.processIdentifier != ownPID }
    }

    // Async function called by the master enforcement task.
    private func perform(
        actions: [WindowAction],
        on app: NSRunningApplication,
        allWindows: [RuleWindowTarget],
        targetWindows: [RuleWindowTarget],
        performGlobalHotkeys: Bool
    ) async {
        let previousApp = NSWorkspace.shared.frontmostApplication
        debugLog("perform app=\(app.localizedName ?? "<unknown>") pid=\(app.processIdentifier) actions=\(actionDebugSummary(actions)) targetWindows=[\(targetWindows.map { String($0.id) }.joined(separator: ","))] allWindows=\(allWindows.count)")

        for action in actions {
            // Check cancellation before every action
            if Task.isCancelled { return }
            
            switch action {
            case .ifCondition(_), .endIf:
                // Conditions are evaluated before execution and never reach
                // this method as executable actions. Keep this defensive case
                // for malformed data loaded from older versions.
                continue
            case .hide:
                if targetWindows.isEmpty {
                    debugLog("hide app-level because target window list is empty")
                    hideApp(app, sourceSpaceIDs: Set(allWindows.flatMap(\.spaceIDs)))
                    continue
                }

                // AXHidden is an application-level attribute on macOS. When
                // every known window is part of this plan, use the native
                // application operation instead of treating a successful
                // per-window AX write as proof that anything was hidden.
                // This is especially important for minimized windows, whose
                // individual AX elements can accept the write without
                // changing the visible application state.
                if targetWindows.count == allWindows.count {
                    debugLog("hide app-level because all windows match")
                    hideApp(app, sourceSpaceIDs: Set(allWindows.flatMap(\.spaceIDs)))
                    continue
                }

                var didHideWindow = false
                for window in targetWindows {
                    if await setHiddenWithRetry(window, isHidden: true) {
                        managedHides[window.id] = window
                        didHideWindow = true
                    }
                }

                // AX exposes app hiding on every supported macOS release, but
                // some applications do not expose a settable window-hidden
                // attribute. Preserve the old behavior only when the plan
                // covers the complete application.
                if !didHideWindow && targetWindows.count == allWindows.count {
                    hideApp(app)
                }
                
            case .show:
                let canApplyAppVisibility = targetWindows.count == allWindows.count
                let wasHidden = canApplyAppVisibility && app.isHidden
                debugLog("show: canApplyAppVisibility=\(canApplyAppVisibility) appHiddenBefore=\(app.isHidden) managedAppHide=\(managedAppHides[app.processIdentifier] != nil)")
                if canApplyAppVisibility,
                   managedAppHides[app.processIdentifier] != nil,
                   unhideAppWithoutActivation(app) {
                    managedAppHides.removeValue(forKey: app.processIdentifier)
                }

                for window in targetWindows {
                    if await setHiddenWithRetry(window, isHidden: false) {
                        managedHides.removeValue(forKey: window.id)
                    }
                    if WindowSpaceService.setMinimized(window, isMinimized: false) {
                        managedMinimizes.remove(window.id)
                    }
                }

                if canApplyAppVisibility && managedAppMinimizes.contains(app.processIdentifier) {
                    unminimizeAppWindows(app)
                    managedAppMinimizes.remove(app.processIdentifier)
                }
                if canApplyAppVisibility && targetWindows.isEmpty {
                    unminimizeAppWindows(app)
                }
                if wasHidden { try? await Task.sleep(nanoseconds: 200_000_000) }
                
            case .restore:
                let canApplyAppVisibility = targetWindows.count == allWindows.count
                debugLog("restore: canApplyAppVisibility=\(canApplyAppVisibility) appHiddenBefore=\(app.isHidden) managedAppHideSources=\(managedAppHides[app.processIdentifier]?.sorted().joined(separator: ",") ?? "none") managedWindowHides=\(managedHides.keys.sorted().map(String.init).joined(separator: ","))")
                if canApplyAppVisibility,
                   managedAppHides[app.processIdentifier] != nil,
                   unhideAppWithoutActivation(app) {
                    managedAppHides.removeValue(forKey: app.processIdentifier)
                    debugLog("restore: application unhide succeeded; appHiddenAfter=\(app.isHidden)")
                } else if canApplyAppVisibility, managedAppHides[app.processIdentifier] != nil {
                    debugLog("restore: application unhide failed; appHiddenAfter=\(app.isHidden)")
                }

                if canApplyAppVisibility && managedAppMinimizes.contains(app.processIdentifier) {
                    unminimizeAppWindows(app)
                    managedAppMinimizes.remove(app.processIdentifier)
                }

                var restoredHiddenWindow = false
                for window in targetWindows {
                    let wasManaged = managedHides[window.id] != nil
                    let didUnhide: Bool
                    if wasManaged {
                        didUnhide = await setHiddenWithRetry(window, isHidden: false)
                    } else {
                        didUnhide = false
                    }
                    debugLog("restore window id=\(window.id): managed=\(wasManaged) unhide=\(didUnhide)")
                    if didUnhide {
                        managedHides.removeValue(forKey: window.id)
                        restoredHiddenWindow = true
                    }
                    let wasManagedMinimized = managedMinimizes.contains(window.id)
                    if wasManagedMinimized,
                       WindowSpaceService.setMinimized(window, isMinimized: false) {
                        managedMinimizes.remove(window.id)
                        debugLog("restore window id=\(window.id): unminimized managed window")
                    }
                }
                if restoredHiddenWindow { try? await Task.sleep(nanoseconds: 200_000_000) }
                
            case .minimize:
                if targetWindows.isEmpty {
                    if !isAppEffectivelyHidden(app) {
                        if minimizeAppWindows(app) {
                            managedAppMinimizes.insert(app.processIdentifier)
                        }
                    } else {
                        minimizeAppWindows(app)
                    }
                    continue
                }

                for window in targetWindows {
                    if !isWindowMinimized(window), WindowSpaceService.setMinimized(window, isMinimized: true) {
                        managedMinimizes.insert(window.id)
                    }
                }
                
            case .bringToFront:
                app.activate(options: .activateIgnoringOtherApps)
                if targetWindows.isEmpty {
                    continue
                }
                for window in targetWindows {
                    _ = WindowSpaceService.raise(window)
                }
                
            case .globalHotkey(let k, let m):
                if performGlobalHotkeys {
                    simulateHotkey(keyCode: k, modifiers: m)
                }
                
            case .hotkey(let k, let m, let restoreWindow, let waitFrontmost):
                await performHotkey(
                    keyCode: k,
                    modifiers: m,
                    restoreWindow: restoreWindow,
                    waitFrontmost: waitFrontmost,
                    on: app,
                    targetWindow: targetWindows.first,
                    previousApp: previousApp
                )
            }
        }
    }

    private func hideApp(_ app: NSRunningApplication, sourceSpaceIDs: Set<String> = []) {
        debugLog("hide app request: app=\(app.localizedName ?? "<unknown>") pid=\(app.processIdentifier) hiddenBefore=\(app.isHidden) sourceSpaces=[\(sourceSpaceIDs.sorted().joined(separator: ","))]")
        if !app.isHidden {
            managedAppHides[app.processIdentifier] = sourceSpaceIDs
        }
        app.hide()
        debugLog("hide app request completed: hiddenAfter=\(app.isHidden) managedSources=\(managedAppHides[app.processIdentifier]?.sorted().joined(separator: ",") ?? "none")")
    }

    private func setHiddenWithRetry(
        _ window: RuleWindowTarget,
        isHidden: Bool
    ) async -> Bool {
        for attempt in 0..<3 {
            if Task.isCancelled { return false }
            let result = WindowSpaceService.setHiddenResult(window, isHidden: isHidden)
            debugLog("AX hidden write: window=\(window.id) desired=\(isHidden) attempt=\(attempt + 1)/3 result=\(result.rawValue) observed=\(boolDebug(WindowSpaceService.isHidden(window)))")
            if result == .success {
                return true
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return false
    }

    private func isWindowMinimized(_ target: RuleWindowTarget) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            target.accessibilityElement,
            kAXMinimizedAttribute as CFString,
            &value
        ) == .success else {
            return false
        }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false
    }

    private func performHotkey(
        keyCode: Int,
        modifiers: UInt,
        restoreWindow: Bool,
        waitFrontmost: Bool,
        on app: NSRunningApplication,
        targetWindow: RuleWindowTarget?,
        previousApp: NSRunningApplication?
    ) async {
        if waitFrontmost {
            var retries = 0
            while !app.isActive && retries < 100 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
                retries += 1
            }

            if !app.isActive { return }
            if let targetWindow {
                _ = WindowSpaceService.raise(targetWindow)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        } else {
            var attempts = 0
            while !app.isActive && attempts < 5 {
                if Task.isCancelled { return }
                app.activate(options: .activateIgnoringOtherApps)
                if let targetWindow {
                    _ = WindowSpaceService.raise(targetWindow)
                }

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

        if Task.isCancelled { return }
        simulateHotkey(keyCode: keyCode, modifiers: modifiers)

        if !waitFrontmost,
           restoreWindow,
           let previousApp,
           previousApp.processIdentifier != app.processIdentifier {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !Task.isCancelled {
                previousApp.activate(options: .activateIgnoringOtherApps)
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
    
    @discardableResult
    private func unhideAppWithoutActivation(_ app: NSRunningApplication) -> Bool {
        if !checkAccessibility() {
            debugLog("application unhide skipped: Accessibility permission missing")
            return false
        }
        let pid = app.processIdentifier; let appElement = AXUIElementCreateApplication(pid)
        let result = AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, kCFBooleanFalse)
        debugLog("application unhide AX write: app=\(app.localizedName ?? "<unknown>") pid=\(pid) result=\(result.rawValue) hiddenAfter=\(app.isHidden)")
        return result == .success
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

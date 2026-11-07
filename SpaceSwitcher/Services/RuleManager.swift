import Foundation
import AppKit
import Combine
import ApplicationServices
import os.log

class RuleManager: ObservableObject {
    @Published var rules: [AppRule] = [] {
        didSet {
            saveRules()
            scheduleRulesRefresh()
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
    private var rulesRefreshTask: Task<Void, Never>?
    private let debugLogger = Logger(subsystem: "dev.mqiu.SpaceSwitcher", category: "Rules")
    
    init() { 
        loadRules() 
        self.isAutomationEnabled = UserDefaults.standard.object(forKey: "isAutomationEnabled") as? Bool ?? true
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        let message = message()
        print("[SpaceSwitcher][Rules] \(message)")
        debugLogger.info("\(message, privacy: .public)")
    }

    private func setupBindings() {
        spaceManager?.$ruleEvaluationSpaceID
            .dropFirst().removeDuplicates()
            .sink { [weak self] spaceID in
                guard let self = self, let spaceID = spaceID else { return }
                self.debugLog("space change received: evaluationSpace=\(spaceID), activeDisplaySpace=\(self.spaceManager?.currentSpaceID ?? "nil"), settling=150ms")
                // SpaceAPI can publish the new desktop before WindowServer and
                // Accessibility have finished updating window membership.
                self.applyRules(for: spaceID, settlingDelay: 150_000_000)
            }
            .store(in: &cancellables)

        spaceManager?.$availableSpaces
            .dropFirst()
            .sink { [weak self] spaces in
                self?.migrateManagedSpaceReferences(using: spaces)
            }
            .store(in: &cancellables)
    }

    private func migrateManagedSpaceReferences(using spaces: [SpaceInfo]) {
        var managedToStableIDs: [String: String] = [:]
        for space in spaces {
            if let managedSpaceID = space.managedSpaceID, managedSpaceID != space.id {
                managedToStableIDs[managedSpaceID] = space.id
            }
        }
        guard !managedToStableIDs.isEmpty else { return }

        var updatedRules = rules
        var didUpdate = false
        for ruleIndex in updatedRules.indices {
            for groupIndex in updatedRules[ruleIndex].groups.indices {
                let originalIDs = updatedRules[ruleIndex].groups[groupIndex].targetSpaceIDs
                let stableIDs = Set(originalIDs.map { managedToStableIDs[$0] ?? $0 })
                guard stableIDs != originalIDs else { continue }
                updatedRules[ruleIndex].groups[groupIndex].targetSpaceIDs = stableIDs
                didUpdate = true
            }
        }

        if didUpdate {
            debugLog("migrated saved rule targets to DesktopRenamer stable space IDs")
            rules = updatedRules
        }
    }
    
    func forceRefresh() {
        guard let spaceID = spaceManager?.currentSpaceID else { return }
        debugLog("force refresh: current=\(spaceID)")
        // Always run on main thread via the Task manager
        self.applyRules(for: spaceID)
    }

    private func scheduleRulesRefresh() {
        rulesRefreshTask?.cancel()
        rulesRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 75_000_000)
            guard !Task.isCancelled, let self else { return }
            self.forceRefresh()
        }
    }

    private func applyRules(for spaceID: String, settlingDelay: UInt64 = 0) {
        debugLog("apply start: space=\(spaceID), delay=\(settlingDelay / 1_000_000)ms, enabled=\(isAutomationEnabled)")
        enforcementTask?.cancel()

        // Capture the ordered list for this refresh. A later edit or reorder
        // cancels this task and schedules a new evaluation with the new order.
        let orderedRules = rules
        enforcementTask = Task { [weak self] in
            guard let self else { return }
            guard isAutomationEnabled else {
                self.debugLog("apply skipped: automation disabled")
                return
            }

            if settlingDelay > 0 {
                try? await Task.sleep(nanoseconds: settlingDelay)
                guard !Task.isCancelled,
                      self.spaceManager?.ruleEvaluationSpaceID == spaceID else {
                    self.debugLog("apply cancelled after settling: requested=\(spaceID), evaluationSpace=\(self.spaceManager?.ruleEvaluationSpaceID ?? "nil"), activeDisplaySpace=\(self.spaceManager?.currentSpaceID ?? "nil")")
                    return
                }
            }

            let applications = self.applications(for: orderedRules)
            self.debugLog("rule order: \(orderedRules.map { $0.appName.isEmpty ? "<all>" : $0.appName }.joined(separator: " -> "))")
            self.debugLog("candidate applications=\(applications.count)")

            // Snapshot and evaluate every app before executing anything. Actions
            // such as Bring to Front or shortcuts can change the focused window;
            // frontmost conditions must all observe the same pre-action state.
            var executionBatches: [ApplicationExecutionBatch] = []
            for application in applications {
                if Task.isCancelled { return }

                let liveSnapshot = self.snapshot(for: application)
                let evaluationPlans = RuleEvaluationEngine.plans(
                    for: liveSnapshot.model,
                    rules: orderedRules,
                    currentSpaceID: spaceID
                )
                let targetsByID = Dictionary(uniqueKeysWithValues: liveSnapshot.windows.map { ($0.id, $0) })
                let plans = evaluationPlans.map { plan in
                    RuleWindowPlan(
                        ruleID: plan.ruleID,
                        actions: plan.actions,
                        windows: plan.windowIDs.compactMap { targetsByID[$0] }
                    )
                }

                self.debugLog("app \(application.localizedName ?? "<unknown>") pid=\(application.processIdentifier) hidden=\(application.isHidden) active=\(application.isActive) AXWindows=\(liveSnapshot.windows.count) managedAppHideSources=\(self.managedAppHides[application.processIdentifier]?.sorted().joined(separator: ",") ?? "none") plans=\(plans.count)")
                for window in liveSnapshot.windows {
                    self.debugLog(self.windowDebugSummary(window, prefix: "  AX window"))
                }
                for plan in plans {
                    self.debugLog("  rule=\(plan.ruleID.uuidString.prefix(8)) actions=\(self.actionDebugSummary(plan.actions)) windows=[\(plan.windows.map { String($0.id) }.joined(separator: ","))]")
                }

                executionBatches.append(
                    ApplicationExecutionBatch(
                        application: application,
                        snapshot: liveSnapshot,
                        plans: plans
                    )
                )
            }

            var changedRuleIDs = Set<UUID>()
            var changedApplicationPIDs = Set<Int32>()
            var changeSummariesByApplication: [Int32: RuleHUDChangeSummary] = [:]

            for batch in executionBatches {
                if Task.isCancelled { break }
                var didPerformGlobalHotkey = false
                for plan in batch.plans {
                    if Task.isCancelled { break }

                    let hasGlobalHotkey = plan.actions.contains {
                        if case .globalHotkey = $0 { return true }
                        return false
                    }

                    let changeSummary = await self.perform(
                        actions: plan.actions,
                        on: batch.application,
                        allWindows: batch.snapshot.windows,
                        targetWindows: plan.windows,
                        performGlobalHotkeys: hasGlobalHotkey && !didPerformGlobalHotkey
                    )
                    let didChangeState = changeSummary.hasChanges
                    self.debugLog("  rule=\(plan.ruleID.uuidString.prefix(8)) confirmedStateChange=\(didChangeState)")
                    if didChangeState {
                        changedRuleIDs.insert(plan.ruleID)
                        changedApplicationPIDs.insert(batch.application.processIdentifier)
                        changeSummariesByApplication[
                            batch.application.processIdentifier,
                            default: RuleHUDChangeSummary()
                        ]
                            .merge(changeSummary)
                    }

                    if hasGlobalHotkey {
                        didPerformGlobalHotkey = true
                    }
                }
            }

            self.debugLog("rule action summary: changedRules=\(changedRuleIDs.count) changedApps=\(changedApplicationPIDs.count) cancelled=\(Task.isCancelled)")
            guard !changedRuleIDs.isEmpty else { return }

            await MainActor.run {
                guard HUDToastSettings.shared.isEnabled else {
                    self.debugLog("HUD toast skipped: setting is disabled")
                    return
                }

                var applicationsByPID: [Int32: NSRunningApplication] = [:]
                for batch in executionBatches where
                    changedApplicationPIDs.contains(batch.application.processIdentifier) {
                    applicationsByPID[batch.application.processIdentifier] = batch.application
                }

                let changedApplications = applicationsByPID.values.sorted {
                    let firstName = $0.localizedName ?? ""
                    let secondName = $1.localizedName ?? ""
                    return firstName.localizedStandardCompare(secondName) == .orderedAscending
                }
                let actionDetails = changedApplications.flatMap { application -> [HUDActionDetail] in
                    guard let summary = changeSummariesByApplication[application.processIdentifier] else {
                        return []
                    }
                    let applicationName = resolvedApplicationName(
                        bundleIdentifier: application.bundleIdentifier ?? "",
                        storedName: application.localizedName ?? "Application"
                    )
                    return summary.localizedOutcomeDetails.map { outcome in
                        HUDActionDetail(
                            text: String(
                                format: NSLocalizedString(
                                    "%@: %@",
                                    comment: "HUD detail with application and confirmed outcome"
                                ),
                                applicationName,
                                outcome
                            ),
                            appIcon: application.icon
                        )
                    }
                }

                let message: String
                if changedApplicationPIDs.count == 1,
                   let processID = changedApplicationPIDs.first,
                   let application = applicationsByPID[processID],
                   let outcomeDescription = changeSummariesByApplication[processID]?.localizedOutcomeDescription {
                    let applicationName = resolvedApplicationName(
                        bundleIdentifier: application.bundleIdentifier ?? "",
                        storedName: application.localizedName ?? "Application"
                    )
                    message = String(
                        format: NSLocalizedString(
                            "%@: %@",
                            comment: "HUD toast with application and confirmed outcomes"
                        ),
                        applicationName,
                        outcomeDescription
                    )
                } else if let outcomeDescription = RuleHUDChangeSummary.localizedApplicationOutcomeDescription(
                    for: changedApplicationPIDs.compactMap { changeSummariesByApplication[$0] }
                ) {
                    message = outcomeDescription
                } else {
                    self.debugLog("HUD toast skipped: no localized outcome summary")
                    return
                }

                let singleApplication = changedApplicationPIDs.count == 1
                    ? changedApplications.first
                    : nil
                let appIcon = singleApplication?.icon ?? NSApp.applicationIconImage

                self.debugLog("HUD toast shown for rules=\(changedRuleIDs.count) apps=\(changedApplicationPIDs.count)")
                HUDWindowController.shared.show(
                    message: message,
                    style: .info,
                    appIcon: appIcon,
                    actionDetails: actionDetails
                )
            }
        }
    }

    private struct LiveApplicationSnapshot {
        let model: RuleApplicationSnapshot
        let windows: [RuleWindowTarget]
    }

    private struct ApplicationExecutionBatch {
        let application: NSRunningApplication
        let snapshot: LiveApplicationSnapshot
        let plans: [RuleWindowPlan]
    }

    private func snapshot(for application: NSRunningApplication) -> LiveApplicationSnapshot {
        var allWindows = WindowSpaceService.windows(for: application)
        let knownWindowIDs = Set(allWindows.map(\.id))

        // A hidden AX window may disappear temporarily. Retain the target that
        // this manager changed so the next source-space pass can still restore
        // it and so it participates in precedence evaluation.
        allWindows.append(contentsOf: managedHides.values.filter {
            $0.applicationPID == application.processIdentifier
                && !knownWindowIDs.contains($0.id)
        })
        allWindows.sort { $0.id < $1.id }

        let windows = allWindows.map { window in
            let mappedSourceSpaceID: String?
            if let managedSpaceID = window.primarySpaceID {
                mappedSourceSpaceID = self.spaceManager?
                    .ruleSpaceIDs(forManagedSpaceIDs: [managedSpaceID])
                    .first ?? managedSpaceID
            } else {
                mappedSourceSpaceID = nil
            }

            return RuleWindowSnapshot(
                id: window.id,
                spaceIDs: spaceManager?.ruleSpaceIDs(forManagedSpaceIDs: window.spaceIDs) ?? window.spaceIDs,
                primarySpaceID: mappedSourceSpaceID,
                isMinimized: WindowSpaceService.isMinimized(window) ?? window.isMinimized,
                isHidden: WindowSpaceService.isHidden(window) ?? window.isHidden,
                isFullscreen: window.isFullscreen,
                isFrontmost: window.isFrontmost
            )
        }

        return LiveApplicationSnapshot(
            model: RuleApplicationSnapshot(
                bundleIdentifier: application.bundleIdentifier ?? "",
                windows: windows,
                managedAppHideSourceSpaceIDs: managedAppHides[application.processIdentifier] ?? []
            ),
            windows: allWindows
        )
    }

    private func ruleSpaceIDs(for windows: [RuleWindowTarget]) -> Set<String> {
        let managedSpaceIDs = Set(windows.flatMap { window in
            window.primarySpaceID.map { [$0] } ?? Array(window.spaceIDs)
        })
        return spaceManager?.ruleSpaceIDs(forManagedSpaceIDs: managedSpaceIDs) ?? managedSpaceIDs
    }

    private func windowDebugSummary(_ window: RuleWindowTarget, prefix: String = "window") -> String {
        let liveMinimized = WindowSpaceService.isMinimized(window)
        let liveHidden = WindowSpaceService.isHidden(window)
        return "\(prefix) id=\(window.id) spaces=[\(window.spaceIDs.sorted().joined(separator: ","))] primarySpace=\(window.primarySpaceID ?? "unknown") minimized(snapshot=\(boolDebug(window.isMinimized)),live=\(boolDebug(liveMinimized))) hidden(snapshot=\(boolDebug(window.isHidden)),live=\(boolDebug(liveHidden))) frontmost=\(window.isFrontmost)"
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
        let ruleID: UUID
        let actions: [WindowAction]
        var windows: [RuleWindowTarget]
    }

    private func applications(for orderedRules: [AppRule]) -> [NSRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var applicationsByPID: [Int32: NSRunningApplication] = [:]

        if orderedRules.contains(where: { $0.isEnabled && $0.appliesToAllApps }) {
            for application in NSWorkspace.shared.runningApplications where
                application.activationPolicy == .regular &&
                application.processIdentifier != ownPID {
                applicationsByPID[application.processIdentifier] = application
            }
        }

        let bundleIdentifiers = Set(
            orderedRules
                .filter { $0.isEnabled && !$0.appliesToAllApps && !$0.appBundleID.isEmpty }
                .map(\.appBundleID)
        )
        for bundleIdentifier in bundleIdentifiers {
            for application in NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ) where application.processIdentifier != ownPID {
                applicationsByPID[application.processIdentifier] = application
            }
        }

        return applicationsByPID.values.sorted {
            $0.processIdentifier < $1.processIdentifier
        }
    }

    // Async function called by the master enforcement task.
    private func perform(
        actions: [WindowAction],
        on app: NSRunningApplication,
        allWindows: [RuleWindowTarget],
        targetWindows: [RuleWindowTarget],
        performGlobalHotkeys: Bool
    ) async -> RuleHUDChangeSummary {
        var changeSummary = RuleHUDChangeSummary()
        let previousApp = NSWorkspace.shared.frontmostApplication
        debugLog("perform app=\(app.localizedName ?? "<unknown>") pid=\(app.processIdentifier) actions=\(actionDebugSummary(actions)) targetWindows=[\(targetWindows.map { String($0.id) }.joined(separator: ","))] allWindows=\(allWindows.count)")

        for action in actions {
            // Check cancellation before every action
            if Task.isCancelled { return changeSummary }
            
            switch action {
            case .ifCondition(_), .endIf:
                // Conditions are evaluated before execution and never reach
                // this method as executable actions. Keep this defensive case
                // for malformed data loaded from older versions.
                continue
            case .hide:
                if targetWindows.isEmpty {
                    debugLog("hide app-level because target window list is empty")
                    let didHideApp = await hideApp(
                        app,
                        sourceSpaceIDs: ruleSpaceIDs(for: allWindows)
                    )
                    if didHideApp {
                        changeSummary.record(.hidden, windowIDs: allWindows.map(\.id))
                    }
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
                    let allTargetWindowsHidden = targetWindows.allSatisfy {
                        isWindowHidden($0) == true
                    }
                    debugLog("hide app-level because all windows match")
                    let didHideApp = await hideApp(
                        app,
                        sourceSpaceIDs: ruleSpaceIDs(for: allWindows)
                    )
                    if !allTargetWindowsHidden && didHideApp {
                        changeSummary.record(.hidden, windowIDs: targetWindows.map(\.id))
                    }
                    continue
                }

                var didHideWindow = false
                for window in targetWindows {
                    let wasHidden = isWindowHidden(window)
                    let wasManagedHide = managedHides[window.id] != nil
                    if await setHiddenWithRetry(window, isHidden: true) {
                        managedHides[window.id] = window
                        let observedAfter = await waitForWindowState(
                            window,
                            targetValue: true,
                            readState: WindowSpaceService.isHidden
                        )
                        let didHide = RuleActionStateChange.isConfirmedAfterUpdate(
                            from: wasHidden,
                            to: true,
                            updateSucceeded: true,
                            observedAfter: observedAfter,
                            wasPreviouslyManaged: wasManagedHide
                        )
                        if didHide {
                            changeSummary.record(.hidden, windowIDs: [window.id])
                        }
                        didHideWindow = didHide || didHideWindow
                    }
                }
                // AX exposes app hiding on every supported macOS release, but
                // some applications do not expose a settable window-hidden
                // attribute. Preserve the old behavior only when the plan
                // covers the complete application.
                if !didHideWindow && targetWindows.count == allWindows.count {
                    if await hideApp(app) {
                        changeSummary.record(.hidden, windowIDs: targetWindows.map(\.id))
                    }
                }
                
            case .show:
                let canApplyAppVisibility = targetWindows.count == allWindows.count
                let wasHidden = canApplyAppVisibility && app.isHidden
                debugLog("show: canApplyAppVisibility=\(canApplyAppVisibility) appHiddenBefore=\(app.isHidden) managedAppHide=\(managedAppHides[app.processIdentifier] != nil)")
                if canApplyAppVisibility {
                    // Show is intentionally forceful: the app may have been
                    // hidden outside SpaceSwitcher, so do not gate this on our
                    // managed-hide bookkeeping (which Restore uses instead).
                    if unhideAppWithoutActivation(app) {
                        managedAppHides.removeValue(forKey: app.processIdentifier)
                        if wasHidden {
                            changeSummary.record(.shown, windowIDs: allWindows.map(\.id))
                        }
                    }
                }

                for window in targetWindows {
                    let wasHidden = isWindowHidden(window)
                    let wasManagedHide = managedHides[window.id] != nil
                    if await setHiddenWithRetry(window, isHidden: false) {
                        managedHides.removeValue(forKey: window.id)
                        let observedAfter = await waitForWindowState(
                            window,
                            targetValue: false,
                            readState: WindowSpaceService.isHidden
                        )
                        let didShow = RuleActionStateChange.isConfirmed(
                            from: wasHidden,
                            to: false,
                            updateSucceeded: true,
                            observedAfter: observedAfter
                        ) || (wasManagedHide && wasHidden == nil && observedAfter == false)
                        if didShow {
                            changeSummary.record(.shown, windowIDs: [window.id])
                        }
                    }

                    let wasMinimized = isWindowMinimized(window)
                    let wasManagedMinimize = managedMinimizes.contains(window.id)
                    if WindowSpaceService.setMinimized(window, isMinimized: false) {
                        managedMinimizes.remove(window.id)
                        let observedAfter = await waitForWindowState(
                            window,
                            targetValue: false,
                            readState: WindowSpaceService.isMinimized
                        )
                        let didShow = RuleActionStateChange.isConfirmed(
                            from: wasMinimized,
                            to: false,
                            updateSucceeded: true,
                            observedAfter: observedAfter
                        ) || (wasManagedMinimize && wasMinimized == nil && observedAfter == false)
                        if didShow {
                            changeSummary.record(.shown, windowIDs: [window.id])
                        }
                    }
                }

                if canApplyAppVisibility && managedAppMinimizes.contains(app.processIdentifier) {
                    if unminimizeAppWindows(app) {
                        changeSummary.record(.shown, windowIDs: allWindows.map(\.id))
                    }
                    managedAppMinimizes.remove(app.processIdentifier)
                }
                if canApplyAppVisibility && targetWindows.isEmpty {
                    if unminimizeAppWindows(app) {
                        changeSummary.record(.shown, windowIDs: allWindows.map(\.id))
                    }
                }
                if wasHidden { try? await Task.sleep(nanoseconds: 200_000_000) }
                
            case .restore:
                let canApplyAppVisibility = targetWindows.count == allWindows.count
                debugLog("restore: canApplyAppVisibility=\(canApplyAppVisibility) appHiddenBefore=\(app.isHidden) managedAppHideSources=\(managedAppHides[app.processIdentifier]?.sorted().joined(separator: ",") ?? "none") managedWindowHides=\(managedHides.keys.sorted().map(String.init).joined(separator: ","))")
                if canApplyAppVisibility, managedAppHides[app.processIdentifier] != nil {
                    let wasHidden = app.isHidden
                    if unhideAppWithoutActivation(app) {
                        managedAppHides.removeValue(forKey: app.processIdentifier)
                        if wasHidden {
                            changeSummary.record(.restored, windowIDs: allWindows.map(\.id))
                        }
                        debugLog("restore: application unhide succeeded; appHiddenAfter=\(app.isHidden)")
                    } else {
                        debugLog("restore: application unhide failed; appHiddenAfter=\(app.isHidden)")
                    }
                }

                if canApplyAppVisibility && managedAppMinimizes.contains(app.processIdentifier) {
                    if unminimizeAppWindows(app) {
                        changeSummary.record(.restored, windowIDs: allWindows.map(\.id))
                    }
                    managedAppMinimizes.remove(app.processIdentifier)
                }

                var restoredHiddenWindow = false
                for window in targetWindows {
                    let wasManaged = managedHides[window.id] != nil
                    let didUnhide: Bool
                    let wasHidden = isWindowHidden(window)
                    if wasManaged {
                        didUnhide = await setHiddenWithRetry(window, isHidden: false)
                    } else {
                        didUnhide = false
                    }
                    debugLog("restore window id=\(window.id): managed=\(wasManaged) unhide=\(didUnhide)")
                    if didUnhide {
                        managedHides.removeValue(forKey: window.id)
                        restoredHiddenWindow = true
                        let observedAfter = await waitForWindowState(
                            window,
                            targetValue: false,
                            readState: WindowSpaceService.isHidden
                        )
                        let didRestore = RuleActionStateChange.isConfirmed(
                            from: wasHidden,
                            to: false,
                            updateSucceeded: true,
                            observedAfter: observedAfter
                        ) || (wasHidden == nil && observedAfter == false)
                        if didRestore {
                            changeSummary.record(.restored, windowIDs: [window.id])
                        }
                    }
                    let wasManagedMinimized = managedMinimizes.contains(window.id)
                    let wasMinimized = isWindowMinimized(window)
                    if wasManagedMinimized {
                        if WindowSpaceService.setMinimized(window, isMinimized: false) {
                            managedMinimizes.remove(window.id)
                            let observedAfter = await waitForWindowState(
                                window,
                                targetValue: false,
                                readState: WindowSpaceService.isMinimized
                            )
                            let didRestore = RuleActionStateChange.isConfirmed(
                                from: wasMinimized,
                                to: false,
                                updateSucceeded: true,
                                observedAfter: observedAfter
                            ) || (wasMinimized == nil && observedAfter == false)
                            if didRestore {
                                changeSummary.record(.restored, windowIDs: [window.id])
                            }
                            debugLog("restore window id=\(window.id): unminimized managed window")
                        }
                    }
                }
                if restoredHiddenWindow { try? await Task.sleep(nanoseconds: 200_000_000) }
                
            case .minimize:
                if targetWindows.isEmpty {
                    let appWasEffectivelyHidden = isAppEffectivelyHidden(app)
                    if minimizeAppWindows(app) {
                        if !appWasEffectivelyHidden {
                            managedAppMinimizes.insert(app.processIdentifier)
                        }
                        changeSummary.record(.minimized, windowIDs: allWindows.map(\.id))
                    }
                    continue
                }

                for window in targetWindows {
                    let wasMinimized = isWindowMinimized(window)
                    let wasManagedMinimize = managedMinimizes.contains(window.id)
                    if wasMinimized != true,
                       WindowSpaceService.setMinimized(window, isMinimized: true) {
                        managedMinimizes.insert(window.id)
                        let observedAfter = await waitForWindowState(
                            window,
                            targetValue: true,
                            readState: WindowSpaceService.isMinimized
                        )
                        let didMinimize = RuleActionStateChange.isConfirmedAfterUpdate(
                            from: wasMinimized,
                            to: true,
                            updateSucceeded: true,
                            observedAfter: observedAfter,
                            wasPreviouslyManaged: wasManagedMinimize
                        )
                        if didMinimize {
                            changeSummary.record(.minimized, windowIDs: [window.id])
                        }
                    }
                }
                
            case .bringToFront:
                let wasActive = app.isActive
                if app.activate(options: .activateIgnoringOtherApps) {
                    if !wasActive {
                        changeSummary.record(.broughtToFront, windowIDs: targetWindows.map(\.id))
                    }
                }
                if targetWindows.isEmpty {
                    continue
                }
                for window in targetWindows {
                    let wasFrontmost = window.isFrontmost
                    if WindowSpaceService.raise(window) {
                        if !wasFrontmost {
                            changeSummary.record(.broughtToFront, windowIDs: [window.id])
                        }
                    }
                }
                
            case .globalHotkey(let k, let m):
                if performGlobalHotkeys,
                   simulateHotkey(keyCode: k, modifiers: m) {
                    changeSummary.record(.shortcutTriggered, windowIDs: [])
                }
                
            case .hotkey(let k, let m, let restoreWindow, let waitFrontmost):
                let didTriggerHotkey = await performHotkey(
                    keyCode: k,
                    modifiers: m,
                    restoreWindow: restoreWindow,
                    waitFrontmost: waitFrontmost,
                    on: app,
                    targetWindow: targetWindows.first,
                    previousApp: previousApp
                )
                if didTriggerHotkey {
                    changeSummary.record(.shortcutTriggered, windowIDs: [])
                }
            }
        }

        return changeSummary
    }

    private func hideApp(_ app: NSRunningApplication, sourceSpaceIDs: Set<String> = []) async -> Bool {
        let wasHidden = app.isHidden
        debugLog("hide app request: app=\(app.localizedName ?? "<unknown>") pid=\(app.processIdentifier) hiddenBefore=\(wasHidden) sourceSpaces=[\(sourceSpaceIDs.sorted().joined(separator: ","))]")
        if !wasHidden {
            managedAppHides[app.processIdentifier] = sourceSpaceIDs
        }
        let didHide = app.hide()
        if !wasHidden {
            // The hide request can reach the target before Launch Services
            // reflects the new state through NSRunningApplication.isHidden.
            // Poll briefly so a real app hide is not discarded as unchanged.
            for attempt in 0..<4 {
                if app.isHidden {
                    debugLog("hide app request completed: requested=\(didHide) hiddenAfter=true managedSources=\(managedAppHides[app.processIdentifier]?.sorted().joined(separator: ",") ?? "none")")
                    return true
                }
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        }
        debugLog("hide app request completed: requested=\(didHide) hiddenAfter=\(app.isHidden) managedSources=\(managedAppHides[app.processIdentifier]?.sorted().joined(separator: ",") ?? "none")")
        return false
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

    private func isWindowHidden(_ target: RuleWindowTarget) -> Bool? {
        WindowSpaceService.isHidden(target) ?? target.isHidden
    }

    private func isWindowMinimized(_ target: RuleWindowTarget) -> Bool? {
        WindowSpaceService.isMinimized(target)
    }

    private func waitForWindowState(
        _ window: RuleWindowTarget,
        targetValue: Bool,
        readState: (RuleWindowTarget) -> Bool?
    ) async -> Bool? {
        for attempt in 0..<3 {
            if Task.isCancelled {
                return readState(window)
            }

            let observedState = readState(window)
            if observedState == targetValue || attempt == 2 {
                return observedState
            }

            try? await Task.sleep(nanoseconds: 40_000_000)
        }

        return readState(window)
    }

    private func performHotkey(
        keyCode: Int,
        modifiers: UInt,
        restoreWindow: Bool,
        waitFrontmost: Bool,
        on app: NSRunningApplication,
        targetWindow: RuleWindowTarget?,
        previousApp: NSRunningApplication?
    ) async -> Bool {
        if waitFrontmost {
            var retries = 0
            while !app.isActive && retries < 100 {
                if Task.isCancelled { return false }
                try? await Task.sleep(nanoseconds: 50_000_000)
                retries += 1
            }

            if !app.isActive { return false }
            if let targetWindow {
                _ = WindowSpaceService.raise(targetWindow)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        } else {
            var attempts = 0
            while !app.isActive && attempts < 5 {
                if Task.isCancelled { return false }
                _ = app.activate(options: .activateIgnoringOtherApps)
                if let targetWindow {
                    _ = WindowSpaceService.raise(targetWindow)
                }

                var check = 0
                while !app.isActive && check < 5 {
                    if Task.isCancelled { return false }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    check += 1
                }
                attempts += 1
            }

            if app.isActive {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        if Task.isCancelled { return false }
        let didPostHotkey = simulateHotkey(keyCode: keyCode, modifiers: modifiers)

        if !waitFrontmost,
           restoreWindow,
           let previousApp,
           previousApp.processIdentifier != app.processIdentifier {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !Task.isCancelled {
                _ = previousApp.activate(options: .activateIgnoringOtherApps)
            }
        }

        return didPostHotkey
    }
    
    private func simulateHotkey(keyCode: Int, modifiers: UInt) -> Bool {
        guard keyCode >= 0 else { return false }
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) else { return false }
        keyDown.flags = flags
        keyDown.post(tap: .cghidEventTap)
        
        usleep(10000)
        
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return false }
        keyUp.flags = flags
        keyUp.post(tap: .cghidEventTap)
        return true
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
    private func unminimizeAppWindows(_ app: NSRunningApplication) -> Bool {
        if !checkAccessibility() {
            print("RULE: Accessibility permission missing, skipping unminimize")
            return false
        }
        let pid = app.processIdentifier; let appElement = AXUIElementCreateApplication(pid); var windowsRef: AnyObject?
        var didUnminimizeSomething = false
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows { 
                var isMin: AnyObject?
                if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMin) == .success, let minBool = isMin as? Bool, minBool { 
                    let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) 
                    if result == .success {
                        didUnminimizeSomething = true
                    } else {
                        print("RULE: Failed to unminimize window: \(result.rawValue)")
                    }
                } 
            }
        }
        return didUnminimizeSomething
    }
    func addRule(_ rule: AppRule) {
        rules.append(rule)
    }

    @discardableResult
    func moveRule(sourceID: String, before targetID: String) -> Bool {
        guard let sourceUUID = UUID(uuidString: sourceID),
              let targetUUID = UUID(uuidString: targetID),
              let reordered = RuleOrdering.moving(
                  rules,
                  sourceID: sourceUUID,
                  before: targetUUID
              ) else {
            return false
        }

        rules = reordered
        return true
    }

    @discardableResult
    func moveRuleToEnd(sourceID: String) -> Bool {
        guard let sourceUUID = UUID(uuidString: sourceID),
              let reordered = RuleOrdering.movingToEnd(rules, sourceID: sourceUUID) else {
            return false
        }

        rules = reordered
        return true
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

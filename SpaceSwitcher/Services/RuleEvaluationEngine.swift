import Foundation

/// The immutable window state used while evaluating one rule refresh.
///
/// Keeping this separate from `RuleWindowTarget` makes rule precedence and
/// condition matching deterministic. Accessibility objects remain in the
/// runtime layer and are only used after evaluation has completed.
struct RuleWindowSnapshot: Identifiable, Hashable {
    let id: Int
    let spaceIDs: Set<String>
    let primarySpaceID: String?
    let isMinimized: Bool?
    let isHidden: Bool?
    let isFullscreen: Bool?
    let isFrontmost: Bool
}

struct RuleApplicationSnapshot {
    let bundleIdentifier: String
    let windows: [RuleWindowSnapshot]
    let managedAppHideSourceSpaceIDs: Set<String>

    init(
        bundleIdentifier: String,
        windows: [RuleWindowSnapshot],
        managedAppHideSourceSpaceIDs: Set<String> = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.windows = windows
        self.managedAppHideSourceSpaceIDs = managedAppHideSourceSpaceIDs
    }
}

struct RuleExecutionPlan: Equatable {
    let ruleID: UUID
    let actions: [WindowAction]
    /// An empty list means the plan targets the application itself because no
    /// accessibility windows were available. Otherwise the IDs identify the
    /// exact windows claimed by this plan.
    let windowIDs: [Int]
}

enum RuleActionStateChange {
    /// Checks whether a known prior state differs from the requested state.
    static func isConfirmed(
        from currentValue: Bool?,
        to targetValue: Bool,
        updateSucceeded: Bool
    ) -> Bool {
        guard updateSucceeded, let currentValue else { return false }
        return currentValue != targetValue
    }

    /// A successful accessibility write can be a no-op. Confirm the live
    /// value reached the requested state before reporting a user-visible change.
    static func isConfirmed(
        from currentValue: Bool?,
        to targetValue: Bool,
        updateSucceeded: Bool,
        observedAfter: Bool?
    ) -> Bool {
        guard observedAfter == targetValue else { return false }
        return isConfirmed(
            from: currentValue,
            to: targetValue,
            updateSucceeded: updateSucceeded
        )
    }

    /// Uses the post-write value when Accessibility could not report the
    /// previous state. A successful write is only treated as a change the
    /// first time this manager has attempted to manage the target, preventing
    /// repeated refreshes from producing duplicate HUD toasts.
    static func isConfirmedAfterUpdate(
        from currentValue: Bool?,
        to targetValue: Bool,
        updateSucceeded: Bool,
        observedAfter: Bool?,
        wasPreviouslyManaged: Bool
    ) -> Bool {
        guard updateSucceeded, observedAfter == targetValue else { return false }

        if let currentValue {
            return isConfirmed(
                from: currentValue,
                to: targetValue,
                updateSucceeded: true
            )
        }

        return !wasPreviouslyManaged
    }
}

enum RuleHUDOutcome: CaseIterable, Hashable {
    case hidden
    case restored
    case shown
    case minimized
    case broughtToFront
    case shortcutTriggered

    var singularWindowDescription: String? {
        switch self {
        case .hidden: return NSLocalizedString("window hidden", comment: "HUD outcome")
        case .restored: return NSLocalizedString("window restored", comment: "HUD outcome")
        case .shown: return NSLocalizedString("window shown", comment: "HUD outcome")
        case .minimized: return NSLocalizedString("window minimized", comment: "HUD outcome")
        case .broughtToFront: return NSLocalizedString("window brought to front", comment: "HUD outcome")
        case .shortcutTriggered: return nil
        }
    }

    var pluralWindowFormat: String? {
        switch self {
        case .hidden: return NSLocalizedString("%d windows hidden", comment: "HUD outcome")
        case .restored: return NSLocalizedString("%d windows restored", comment: "HUD outcome")
        case .shown: return NSLocalizedString("%d windows shown", comment: "HUD outcome")
        case .minimized: return NSLocalizedString("%d windows minimized", comment: "HUD outcome")
        case .broughtToFront: return NSLocalizedString("%d windows brought to front", comment: "HUD outcome")
        case .shortcutTriggered: return nil
        }
    }

    var applicationDescription: String {
        switch self {
        case .hidden: return NSLocalizedString("app hidden", comment: "HUD outcome")
        case .restored: return NSLocalizedString("app restored", comment: "HUD outcome")
        case .shown: return NSLocalizedString("app shown", comment: "HUD outcome")
        case .minimized: return NSLocalizedString("app minimized", comment: "HUD outcome")
        case .broughtToFront: return NSLocalizedString("app brought to front", comment: "HUD outcome")
        case .shortcutTriggered: return NSLocalizedString("shortcut triggered", comment: "HUD outcome")
        }
    }

    var compactApplicationFormat: String {
        switch self {
        case .hidden: return NSLocalizedString("%d hidden", comment: "HUD count of apps hidden")
        case .restored: return NSLocalizedString("%d restored", comment: "HUD count of apps restored")
        case .shown: return NSLocalizedString("%d shown", comment: "HUD count of apps shown")
        case .minimized: return NSLocalizedString("%d minimized", comment: "HUD count of apps minimized")
        case .broughtToFront:
            return NSLocalizedString("%d brought to front", comment: "HUD count of apps brought to the front")
        case .shortcutTriggered:
            return NSLocalizedString("%d shortcuts triggered", comment: "HUD count of apps with triggered shortcuts")
        }
    }
}

struct RuleHUDChangeSummary {
    private(set) var changedWindowIDs: [RuleHUDOutcome: Set<Int>] = [:]
    private(set) var applicationOutcomes = Set<RuleHUDOutcome>()

    var hasChanges: Bool {
        !applicationOutcomes.isEmpty || changedWindowIDs.values.contains { !$0.isEmpty }
    }

    func windowCount(for outcome: RuleHUDOutcome) -> Int {
        changedWindowIDs[outcome]?.count ?? 0
    }

    func includes(_ outcome: RuleHUDOutcome) -> Bool {
        windowCount(for: outcome) > 0 || applicationOutcomes.contains(outcome)
    }

    mutating func record(_ outcome: RuleHUDOutcome, windowIDs: [Int]) {
        guard !windowIDs.isEmpty else {
            applicationOutcomes.insert(outcome)
            return
        }
        changedWindowIDs[outcome, default: []].formUnion(windowIDs)
    }

    mutating func merge(_ other: RuleHUDChangeSummary) {
        for (outcome, windowIDs) in other.changedWindowIDs {
            changedWindowIDs[outcome, default: []].formUnion(windowIDs)
        }
        applicationOutcomes.formUnion(other.applicationOutcomes)
    }

    var localizedOutcomeDetails: [String] {
        var fragments: [String] = []
        for outcome in RuleHUDOutcome.allCases {
            let count = windowCount(for: outcome)
            if count == 1, let description = outcome.singularWindowDescription {
                fragments.append(description)
            } else if count > 1, let format = outcome.pluralWindowFormat {
                fragments.append(String(format: format, count))
            }
            if applicationOutcomes.contains(outcome) {
                fragments.append(outcome.applicationDescription)
            }
        }
        return fragments
    }

    var localizedOutcomeDescription: String? {
        let fragments = localizedOutcomeDetails
        return fragments.isEmpty ? nil : fragments.joined(separator: ", ")
    }

    static func localizedApplicationOutcomeDescription(
        for summaries: [RuleHUDChangeSummary]
    ) -> String? {
        let outcomeCounts = applicationOutcomeCounts(for: summaries)
        let fragments = RuleHUDOutcome.allCases.compactMap { outcome -> String? in
            guard let count = outcomeCounts[outcome], count > 0 else { return nil }
            return String(format: outcome.compactApplicationFormat, count)
        }
        return fragments.isEmpty ? nil : fragments.joined(separator: ", ")
    }

    static func applicationOutcomeCounts(
        for summaries: [RuleHUDChangeSummary]
    ) -> [RuleHUDOutcome: Int] {
        var counts: [RuleHUDOutcome: Int] = [:]
        for summary in summaries {
            for outcome in RuleHUDOutcome.allCases where summary.includes(outcome) {
                counts[outcome, default: 0] += 1
            }
        }
        return counts
    }
}

enum RuleOrdering {
    static func moving(
        _ rules: [AppRule],
        sourceID: UUID,
        before targetID: UUID
    ) -> [AppRule]? {
        guard sourceID != targetID,
              let sourceIndex = rules.firstIndex(where: { $0.id == sourceID }),
              rules.contains(where: { $0.id == targetID }) else {
            return nil
        }

        var reordered = rules
        let movedRule = reordered.remove(at: sourceIndex)
        guard let targetIndex = reordered.firstIndex(where: { $0.id == targetID }) else {
            return nil
        }
        reordered.insert(movedRule, at: targetIndex)
        return reordered
    }

    static func movingToEnd(
        _ rules: [AppRule],
        sourceID: UUID
    ) -> [AppRule]? {
        guard let sourceIndex = rules.firstIndex(where: { $0.id == sourceID }),
              sourceIndex < rules.count - 1 else {
            return nil
        }

        var reordered = rules
        reordered.append(reordered.remove(at: sourceIndex))
        return reordered
    }
}

/// Evaluates the ordered rule list without performing any AppKit side effects.
/// Rules are considered from top to bottom. A window is claimed only when its
/// selected group/fallback produces at least one executable action, allowing a
/// later catch-all rule to handle windows that an earlier rule cannot handle.
enum RuleEvaluationEngine {
    static func plans(
        for application: RuleApplicationSnapshot,
        rules: [AppRule],
        currentSpaceID: String
    ) -> [RuleExecutionPlan] {
        var claimedWindowIDs = Set<Int>()
        var plans: [RuleExecutionPlan] = []

        for rule in rules where rule.isEnabled && targets(rule: rule, bundleIdentifier: application.bundleIdentifier) {
            if application.windows.isEmpty {
                let rawActions = selectedActions(
                    for: rule,
                    currentSpaceID: currentSpaceID,
                    window: nil,
                    managedSourceSpaceIDs: application.managedAppHideSourceSpaceIDs
                )
                let actions = evaluatedActions(rawActions, window: nil)

                guard !actions.isEmpty else { continue }

                plans.append(RuleExecutionPlan(ruleID: rule.id, actions: actions, windowIDs: []))
                // An app-level plan has no individual windows to leave for a
                // later rule. The first rule with executable actions wins.
                break
            }

            let availableWindows = application.windows.filter {
                !claimedWindowIDs.contains($0.id)
            }
            guard !availableWindows.isEmpty else { break }

            // Hiding an application removes all of its AX windows from some
            // applications. When this manager recorded the source spaces for
            // that app, a matching source-space Restore must unhide the whole
            // app once any source window is visible again.
            if claimedWindowIDs.isEmpty,
               let managedRestoreActions = managedApplicationRestoreActions(
                   for: rule,
                   application: application,
                   currentSpaceID: currentSpaceID
               ) {
                let allWindowIDs = application.windows.map(\.id)
                claimedWindowIDs.formUnion(allWindowIDs)
                plans.append(
                    RuleExecutionPlan(
                        ruleID: rule.id,
                        actions: managedRestoreActions,
                        windowIDs: allWindowIDs
                    )
                )
                break
            }

            var groupedPlans: [(actions: [WindowAction], windowIDs: [Int])] = []

            for window in availableWindows {
                let rawActions = selectedActions(
                    for: rule,
                    currentSpaceID: currentSpaceID,
                    window: window,
                    managedSourceSpaceIDs: application.managedAppHideSourceSpaceIDs
                )
                let actions = evaluatedActions(rawActions, window: window)

                guard !actions.isEmpty else { continue }

                claimedWindowIDs.insert(window.id)
                if let index = groupedPlans.firstIndex(where: { $0.actions == actions }) {
                    groupedPlans[index].windowIDs.append(window.id)
                } else {
                    groupedPlans.append((actions: actions, windowIDs: [window.id]))
                }
            }

            plans.append(contentsOf: groupedPlans.map {
                RuleExecutionPlan(ruleID: rule.id, actions: $0.actions, windowIDs: $0.windowIDs)
            })
        }

        return plans
    }

    private static func targets(rule: AppRule, bundleIdentifier: String) -> Bool {
        rule.appliesToAllApps || (
            !rule.appBundleID.isEmpty && rule.appBundleID == bundleIdentifier
        )
    }

    private static func selectedActions(
        for rule: AppRule,
        currentSpaceID: String,
        window: RuleWindowSnapshot?,
        managedSourceSpaceIDs: Set<String>
    ) -> [ActionItem] {
        let matchingGroup = rule.groups.first { group in
            groupMatches(
                group,
                currentSpaceID: currentSpaceID,
                window: window,
                managedSourceSpaceIDs: managedSourceSpaceIDs
            )
        }
        return matchingGroup?.actions ?? rule.elseActions
    }

    private static func groupMatches(
        _ group: RuleGroup,
        currentSpaceID: String,
        window: RuleWindowSnapshot?,
        managedSourceSpaceIDs: Set<String>
    ) -> Bool {
        if group.targetSpaceIDs.contains(currentSpaceID) {
            return true
        }

        guard group.usesSourceSpace else { return false }
        if let window {
            return window.primarySpaceID.map { $0 == currentSpaceID }
                ?? window.spaceIDs.contains(currentSpaceID)
        }
        return managedSourceSpaceIDs.contains(currentSpaceID)
    }

    private static func managedApplicationRestoreActions(
        for rule: AppRule,
        application: RuleApplicationSnapshot,
        currentSpaceID: String
    ) -> [WindowAction]? {
        guard application.managedAppHideSourceSpaceIDs.contains(currentSpaceID) else { return nil }

        for window in application.windows where window.spaceIDs.contains(currentSpaceID) {
            let rawActions = selectedActions(
                for: rule,
                currentSpaceID: currentSpaceID,
                // The window's live membership can change after the app was
                // hidden. Use the recorded source space to select the group,
                // then evaluate its conditions against the actual window.
                window: nil,
                managedSourceSpaceIDs: application.managedAppHideSourceSpaceIDs
            )

            let actions = evaluatedActions(rawActions, window: window)
            if actions.contains(where: { action in
                if case .restore = action { return true }
                return false
            }) {
                return actions
            }
        }

        return nil
    }

    static func evaluatedActions(
        _ items: [ActionItem],
        window: RuleWindowSnapshot?
    ) -> [WindowAction] {
        var result: [WindowAction] = []
        var isInsideCondition = false
        var conditionPassed = false

        for item in items {
            switch item.value {
            case .ifCondition(let condition):
                // Conditional blocks are flat. A malformed nested If is
                // treated as false until the next End If rather than leaking
                // actions through an invalid block.
                if isInsideCondition {
                    conditionPassed = false
                } else {
                    isInsideCondition = true
                    conditionPassed = conditionMatches(condition, window: window)
                }

            case .endIf:
                isInsideCondition = false
                conditionPassed = false

            default:
                if !isInsideCondition || conditionPassed {
                    result.append(item.value)
                }
            }
        }

        return result
    }

    private static func conditionMatches(
        _ condition: RuleCondition,
        window: RuleWindowSnapshot?
    ) -> Bool {
        guard let window else { return false }

        switch condition {
        case .windowMinimized:
            return window.isMinimized == true
        case .windowFrontmost:
            return window.isFrontmost
        case .windowHidden:
            return window.isHidden == true
        case .windowFullscreen:
            return window.isFullscreen == true
        }
    }
}

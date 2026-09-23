import XCTest
@testable import SpaceSwitcher

final class RuleEvaluationEngineTests: XCTestCase {
    func testSpecificRuleBeforeAllAppsWinsForItsMatchingWindow() {
        let specificRule = makeRule(
            id: uuid(1),
            appBundleID: "com.example.editor",
            groups: [
                RuleGroup(
                    targetSpaceIDs: [],
                    actions: [ActionItem(.restore)],
                    usesSourceSpace: true
                )
            ]
        )
        let allAppsRule = makeRule(
            id: uuid(2),
            appliesToAllApps: true,
            elseActions: [ActionItem(.hide)]
        )
        let application = makeApplication(
            bundleIdentifier: "com.example.editor",
            windows: [
                makeWindow(id: 101, spaces: ["source"]),
                makeWindow(id: 102, spaces: ["other"])
            ]
        )

        let plans = RuleEvaluationEngine.plans(
            for: application,
            rules: [specificRule, allAppsRule],
            currentSpaceID: "source"
        )

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans[0].ruleID, specificRule.id)
        XCTAssertEqual(plans[0].actions, [.restore])
        XCTAssertEqual(plans[0].windowIDs, [101])
        XCTAssertEqual(plans[1].ruleID, allAppsRule.id)
        XCTAssertEqual(plans[1].actions, [.hide])
        XCTAssertEqual(plans[1].windowIDs, [102])
    }

    func testAllAppsRuleAboveSpecificRuleClaimsEveryEligibleWindow() {
        let allAppsRule = makeRule(
            id: uuid(1),
            appliesToAllApps: true,
            elseActions: [ActionItem(.hide)]
        )
        let specificRule = makeRule(
            id: uuid(2),
            appBundleID: "com.example.editor",
            elseActions: [ActionItem(.restore)]
        )
        let application = makeApplication(
            bundleIdentifier: "com.example.editor",
            windows: [
                makeWindow(id: 101, spaces: ["source"]),
                makeWindow(id: 102, spaces: ["other"])
            ]
        )

        let plans = RuleEvaluationEngine.plans(
            for: application,
            rules: [allAppsRule, specificRule],
            currentSpaceID: "source"
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].ruleID, allAppsRule.id)
        XCTAssertEqual(plans[0].actions, [.hide])
        XCTAssertEqual(plans[0].windowIDs, [101, 102])
    }

    func testFalseConditionDoesNotClaimWindowForLaterRule() {
        let conditionalRule = makeRule(
            id: uuid(1),
            appBundleID: "com.example.editor",
            elseActions: [
                ActionItem(.ifCondition(.windowMinimized)),
                ActionItem(.hide),
                ActionItem(.endIf)
            ]
        )
        let fallbackRule = makeRule(
            id: uuid(2),
            appliesToAllApps: true,
            elseActions: [ActionItem(.show)]
        )
        let application = makeApplication(
            bundleIdentifier: "com.example.editor",
            windows: [makeWindow(id: 101, minimized: false)]
        )

        let plans = RuleEvaluationEngine.plans(
            for: application,
            rules: [conditionalRule, fallbackRule],
            currentSpaceID: "source"
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].ruleID, fallbackRule.id)
        XCTAssertEqual(plans[0].actions, [.show])
        XCTAssertEqual(plans[0].windowIDs, [101])
    }

    func testGroupMismatchFallsThroughToLaterRule() {
        let specificRule = makeRule(
            id: uuid(1),
            appBundleID: "com.example.editor",
            groups: [
                RuleGroup(
                    targetSpaceIDs: ["other"],
                    actions: [ActionItem(.restore)]
                )
            ]
        )
        let fallbackRule = makeRule(
            id: uuid(2),
            appliesToAllApps: true,
            elseActions: [ActionItem(.hide)]
        )
        let application = makeApplication(
            bundleIdentifier: "com.example.editor",
            windows: [makeWindow(id: 101, spaces: ["source"])]
        )

        let plans = RuleEvaluationEngine.plans(
            for: application,
            rules: [specificRule, fallbackRule],
            currentSpaceID: "source"
        )

        XCTAssertEqual(plans.map(\.ruleID), [fallbackRule.id])
        XCTAssertEqual(plans[0].actions, [.hide])
    }

    func testDisabledRuleDoesNotClaimWindows() {
        let disabledRule = makeRule(
            id: uuid(1),
            appBundleID: "com.example.editor",
            isEnabled: false,
            elseActions: [ActionItem(.hide)]
        )
        let enabledRule = makeRule(
            id: uuid(2),
            appBundleID: "com.example.editor",
            elseActions: [ActionItem(.show)]
        )

        let plans = RuleEvaluationEngine.plans(
            for: makeApplication(
                bundleIdentifier: "com.example.editor",
                windows: [makeWindow(id: 101)]
            ),
            rules: [disabledRule, enabledRule],
            currentSpaceID: "source"
        )

        XCTAssertEqual(plans.map(\.ruleID), [enabledRule.id])
        XCTAssertEqual(plans[0].actions, [.show])
    }

    func testNoWindowStateAllowsUnconditionalRuleButNotWindowCondition() {
        let conditionalRule = makeRule(
            id: uuid(1),
            appBundleID: "com.example.editor",
            elseActions: [
                ActionItem(.ifCondition(.windowMinimized)),
                ActionItem(.hide),
                ActionItem(.endIf)
            ]
        )
        let unconditionalRule = makeRule(
            id: uuid(2),
            appliesToAllApps: true,
            elseActions: [ActionItem(.show)]
        )

        let plans = RuleEvaluationEngine.plans(
            for: makeApplication(bundleIdentifier: "com.example.editor", windows: []),
            rules: [conditionalRule, unconditionalRule],
            currentSpaceID: "source"
        )

        XCTAssertEqual(plans.map(\.ruleID), [unconditionalRule.id])
        XCTAssertTrue(plans[0].windowIDs.isEmpty)
        XCTAssertEqual(plans[0].actions, [.show])
    }

    func testDifferentWindowsCanProduceDifferentPlansWithinOneRule() {
        let rule = makeRule(
            id: uuid(1),
            appBundleID: "com.example.editor",
            groups: [
                RuleGroup(
                    targetSpaceIDs: [],
                    actions: [ActionItem(.hide)],
                    usesSourceSpace: true
                )
            ],
            elseActions: [ActionItem(.restore)]
        )
        let plans = RuleEvaluationEngine.plans(
            for: makeApplication(
                bundleIdentifier: "com.example.editor",
                windows: [
                    makeWindow(id: 101, spaces: ["source"]),
                    makeWindow(id: 102, spaces: ["other"])
                ]
            ),
            rules: [rule],
            currentSpaceID: "source"
        )

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans[0].actions, [.hide])
        XCTAssertEqual(plans[0].windowIDs, [101])
        XCTAssertEqual(plans[1].actions, [.restore])
        XCTAssertEqual(plans[1].windowIDs, [102])
    }

    func testManagedApplicationRestoreTargetsAllWindows() {
        let rule = makeRule(
            id: uuid(1),
            appBundleID: "com.example.editor",
            groups: [
                RuleGroup(
                    targetSpaceIDs: [],
                    actions: [ActionItem(.restore)],
                    usesSourceSpace: true
                )
            ]
        )
        let application = makeApplication(
            bundleIdentifier: "com.example.editor",
            windows: [
                makeWindow(id: 101, spaces: ["source"]),
                makeWindow(id: 102, spaces: ["other"])
            ],
            managedAppHideSourceSpaceIDs: ["source"]
        )

        let plans = RuleEvaluationEngine.plans(
            for: application,
            rules: [rule],
            currentSpaceID: "source"
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].actions, [.restore])
        XCTAssertEqual(plans[0].windowIDs, [101, 102])
    }

    func testRuleOrderAndRuleOrderingRoundTrip() throws {
        let first = makeRule(id: uuid(1), appBundleID: "com.example.first")
        let second = makeRule(id: uuid(2), appBundleID: "com.example.second")
        let third = makeRule(id: uuid(3), appBundleID: "com.example.third")
        let rules = [first, second, third]

        let moved = try XCTUnwrap(
            RuleOrdering.moving(rules, sourceID: third.id, before: first.id)
        )
        XCTAssertEqual(moved.map(\.id), [third.id, first.id, second.id])

        let movedToEnd = try XCTUnwrap(
            RuleOrdering.movingToEnd(moved, sourceID: third.id)
        )
        XCTAssertEqual(movedToEnd.map(\.id), [first.id, second.id, third.id])

        let reloaded = try JSONDecoder().decode(
            [AppRule].self,
            from: JSONEncoder().encode(moved)
        )
        XCTAssertEqual(reloaded.map(\.id), moved.map(\.id))
    }

    func testLegacyMinimizedWindowConditionMigratesToActionBlock() throws {
        let groupID = uuid(10)
        let json = """
        {
          "id": "\(groupID.uuidString)",
          "targetSpaceIDs": ["source"],
          "windowCondition": "minimized",
          "actions": [{"type": "hide"}]
        }
        """

        let group = try JSONDecoder().decode(
            RuleGroup.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(
            group.actions.map(\.value),
            [.ifCondition(.windowMinimized), .hide, .endIf]
        )
    }

    private func makeApplication(
        bundleIdentifier: String,
        windows: [RuleWindowSnapshot],
        managedAppHideSourceSpaceIDs: Set<String> = []
    ) -> RuleApplicationSnapshot {
        RuleApplicationSnapshot(
            bundleIdentifier: bundleIdentifier,
            windows: windows,
            managedAppHideSourceSpaceIDs: managedAppHideSourceSpaceIDs
        )
    }

    private func makeWindow(
        id: Int,
        spaces: Set<String> = ["source"],
        minimized: Bool? = false,
        hidden: Bool? = false,
        fullscreen: Bool? = false,
        frontmost: Bool = false
    ) -> RuleWindowSnapshot {
        RuleWindowSnapshot(
            id: id,
            spaceIDs: spaces,
            isMinimized: minimized,
            isHidden: hidden,
            isFullscreen: fullscreen,
            isFrontmost: frontmost
        )
    }

    private func makeRule(
        id: UUID,
        appBundleID: String = "",
        appliesToAllApps: Bool = false,
        groups: [RuleGroup] = [],
        isEnabled: Bool = true,
        elseActions: [ActionItem] = []
    ) -> AppRule {
        var rule = AppRule(
            appBundleID: appBundleID,
            appName: appliesToAllApps ? "All Apps" : appBundleID,
            appliesToAllApps: appliesToAllApps,
            groups: groups,
            elseActions: elseActions,
            isEnabled: isEnabled
        )
        rule.id = id
        return rule
    }

    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }
}

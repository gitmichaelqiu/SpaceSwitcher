import XCTest
@testable import SpaceSwitcher

final class RulePresetTests: XCTestCase {
    func testHideMinimizedPresetCreatesSourceSpaceRestoreAndConditionalFallback() {
        let rule = makeRule()
        let result = RulePreset.hideMinimizedOutsideSource.applying(to: rule)

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertTrue(result.groups[0].usesSourceSpace)
        XCTAssertTrue(result.groups[0].targetSpaceIDs.isEmpty)
        XCTAssertEqual(result.groups[0].actions.map(\.value), [.restore])
        XCTAssertEqual(
            result.elseActions.map(\.value),
            [.ifCondition(.windowMinimized), .hide, .endIf]
        )
    }

    func testHidePresetCreatesSourceSpaceRestoreAndHideFallback() {
        let result = RulePreset.hideOutsideSource.applying(to: makeRule())

        XCTAssertEqual(result.groups[0].actions.map(\.value), [.restore])
        XCTAssertEqual(result.elseActions.map(\.value), [.hide])
        XCTAssertTrue(result.groups[0].usesSourceSpace)
        XCTAssertTrue(result.groups[0].targetSpaceIDs.isEmpty)
    }

    func testMinimizePresetCreatesSourceSpaceRestoreAndMinimizeFallback() {
        let result = RulePreset.minimizeOutsideSource.applying(to: makeRule())

        XCTAssertEqual(result.groups[0].actions.map(\.value), [.restore])
        XCTAssertEqual(result.elseActions.map(\.value), [.minimize])
        XCTAssertTrue(result.groups[0].usesSourceSpace)
        XCTAssertTrue(result.groups[0].targetSpaceIDs.isEmpty)
    }

    func testApplyingPresetPreservesRuleIdentityApplicationAndEnabledState() {
        let original = makeRule()

        for preset in RulePreset.allCases {
            let result = preset.applying(to: original)

            XCTAssertEqual(result.id, original.id, preset.rawValue)
            XCTAssertEqual(result.appBundleID, original.appBundleID, preset.rawValue)
            XCTAssertEqual(result.appName, original.appName, preset.rawValue)
            XCTAssertEqual(result.appliesToAllApps, original.appliesToAllApps, preset.rawValue)
            XCTAssertEqual(result.isEnabled, original.isEnabled, preset.rawValue)
        }
    }

    private func makeRule() -> AppRule {
        AppRule(
            appBundleID: "com.example.TestApp",
            appName: "Test App",
            appliesToAllApps: true,
            groups: [
                RuleGroup(
                    targetSpaceIDs: ["space-1"],
                    actions: [ActionItem(.show)]
                )
            ],
            elseActions: [ActionItem(.hide)],
            isEnabled: false
        )
    }
}

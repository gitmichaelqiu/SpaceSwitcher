import XCTest
@testable import SpaceSwitcher

final class RuleTransferServiceTests: XCTestCase {
    func testJSONRoundTripPreservesRuleSettingsAndActions() throws {
        let rule = AppRule(
            appBundleID: "com.example.editor",
            appName: "Editor",
            groups: [
                RuleGroup(
                    targetSpaceIDs: ["space-1"],
                    actions: [
                        ActionItem(.hide),
                        ActionItem(.hotkey(keyCode: 12, modifiers: 256, restoreWindow: true, waitFrontmost: false))
                    ],
                    usesSourceSpace: true
                )
            ],
            elseActions: [ActionItem(.restore)],
            isEnabled: false
        )

        let data = try RuleTransferService.encode([rule])
        let decodedRules = try RuleTransferService.decode(data)

        XCTAssertEqual(decodedRules.count, 1)
        XCTAssertEqual(decodedRules[0].id, rule.id)
        XCTAssertEqual(decodedRules[0].appBundleID, rule.appBundleID)
        XCTAssertEqual(decodedRules[0].appName, rule.appName)
        XCTAssertEqual(decodedRules[0].isEnabled, rule.isEnabled)
        XCTAssertEqual(decodedRules[0].groups[0].id, rule.groups[0].id)
        XCTAssertEqual(decodedRules[0].groups[0].targetSpaceIDs, rule.groups[0].targetSpaceIDs)
        XCTAssertEqual(decodedRules[0].groups[0].usesSourceSpace, rule.groups[0].usesSourceSpace)
        XCTAssertEqual(decodedRules[0].groups[0].actions.map(\.value), rule.groups[0].actions.map(\.value))
        XCTAssertEqual(decodedRules[0].elseActions.map(\.value), rule.elseActions.map(\.value))
    }

    func testDecodeRejectsAnEmptyRuleArray() {
        XCTAssertThrowsError(try RuleTransferService.decode(Data("[]".utf8))) { error in
            XCTAssertEqual(error as? RuleTransferError, .emptyRuleSet)
        }
    }

    func testDecodeRejectsInvalidJSON() {
        XCTAssertThrowsError(try RuleTransferService.decode(Data("not json".utf8)))
    }
}

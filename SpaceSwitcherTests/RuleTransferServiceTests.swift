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

    func testReplaceAllUsesOnlyImportedRules() {
        let current = makeRule(bundleIdentifier: "com.example.current")
        let imported = makeRule(bundleIdentifier: "com.example.imported")

        let result = RuleTransferService.applying(
            [imported],
            to: [current],
            strategy: .replaceAll
        )

        XCTAssertEqual(result.map(\.id), [imported.id])
    }

    func testKeepAllAppendsImportedRulesEvenWhenAppAlreadyExists() {
        let current = makeRule(bundleIdentifier: "com.example.editor")
        let imported = makeRule(bundleIdentifier: "com.example.editor")

        let result = RuleTransferService.applying(
            [imported],
            to: [current],
            strategy: .keepAll
        )

        XCTAssertEqual(result.map(\.appBundleID), [current.appBundleID, imported.appBundleID])
        XCTAssertNotEqual(result[0].id, result[1].id)
    }

    func testAddNewAppsSkipsApplicationsThatAlreadyHaveRules() {
        let current = makeRule(bundleIdentifier: "com.example.editor")
        let duplicateApp = makeRule(bundleIdentifier: "COM.EXAMPLE.EDITOR")
        let newApp = makeRule(bundleIdentifier: "com.example.browser")

        let result = RuleTransferService.applying(
            [duplicateApp, newApp],
            to: [current],
            strategy: .addNewApps
        )

        XCTAssertEqual(result.map(\.appBundleID), [current.appBundleID, newApp.appBundleID])
    }

    func testReplaceMatchingAppsReplacesTheirRulesAndPreservesOtherOrder() {
        let currentEditor = makeRule(bundleIdentifier: "com.example.editor")
        let currentBrowser = makeRule(bundleIdentifier: "com.example.browser")
        let secondCurrentEditor = makeRule(bundleIdentifier: "com.example.editor")
        let importedEditor = makeRule(bundleIdentifier: "com.example.editor")
        let secondImportedEditor = makeRule(bundleIdentifier: "com.example.editor")

        let result = RuleTransferService.applying(
            [importedEditor, secondImportedEditor],
            to: [currentEditor, currentBrowser, secondCurrentEditor],
            strategy: .replaceMatchingApps
        )

        XCTAssertEqual(
            result.map(\.id),
            [importedEditor.id, secondImportedEditor.id, currentBrowser.id]
        )
    }

    private func makeRule(bundleIdentifier: String) -> AppRule {
        AppRule(
            appBundleID: bundleIdentifier,
            appName: bundleIdentifier,
            groups: [],
            elseActions: []
        )
    }
}

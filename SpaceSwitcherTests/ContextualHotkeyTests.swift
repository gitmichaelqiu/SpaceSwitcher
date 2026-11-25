import AppKit
import XCTest
@testable import SpaceSwitcher

final class ContextualHotkeyTests: XCTestCase {
    func testResolverUsesSpaceActionAndUsesFallbackOnlyForKnownUnassignedSpace() {
        let perSpaceAction = ContextualHotkeyAction(
            kind: .openOrActivate,
            appBundleIdentifier: "com.example.research",
            appName: "Research"
        )
        let fallbackAction = ContextualHotkeyAction(
            kind: .activateIfRunning,
            appBundleIdentifier: "com.example.mail",
            appName: "Mail"
        )
        let hotkey = ContextualHotkey(
            keyCode: 31,
            modifiers: UInt(NSEvent.ModifierFlags.command.rawValue),
            spaceActions: [
                ContextualHotkeySpaceAction(spaceID: "research-space", action: perSpaceAction)
            ],
            otherSpacesAction: fallbackAction
        )

        XCTAssertEqual(
            ContextualHotkeySpaceResolver.action(
                for: hotkey,
                currentSpaceID: "research-space",
                knownSpaceIDs: ["research-space", "writing-space"],
                apiIsAvailable: true,
                hotkeysAreEnabled: true
            ),
            perSpaceAction
        )
        XCTAssertEqual(
            ContextualHotkeySpaceResolver.action(
                for: hotkey,
                currentSpaceID: "writing-space",
                knownSpaceIDs: ["research-space", "writing-space"],
                apiIsAvailable: true,
                hotkeysAreEnabled: true
            ),
            fallbackAction
        )
    }

    func testResolverDoesNothingWhenSpaceIdentityIsUnavailableOrUnknown() {
        let hotkey = ContextualHotkey(
            keyCode: 31,
            modifiers: UInt(NSEvent.ModifierFlags.command.rawValue),
            spaceActions: [],
            otherSpacesAction: ContextualHotkeyAction(
                kind: .openOrActivate,
                appBundleIdentifier: "com.example.mail",
                appName: "Mail"
            )
        )

        XCTAssertNil(
            ContextualHotkeySpaceResolver.action(
                for: hotkey,
                currentSpaceID: "stale-space",
                knownSpaceIDs: ["known-space"],
                apiIsAvailable: true,
                hotkeysAreEnabled: true
            )
        )
        XCTAssertNil(
            ContextualHotkeySpaceResolver.action(
                for: hotkey,
                currentSpaceID: "known-space",
                knownSpaceIDs: ["known-space"],
                apiIsAvailable: false,
                hotkeysAreEnabled: true
            )
        )
        XCTAssertNil(
            ContextualHotkeySpaceResolver.action(
                for: hotkey,
                currentSpaceID: "known-space",
                knownSpaceIDs: ["known-space"],
                apiIsAvailable: true,
                hotkeysAreEnabled: false
            )
        )
    }

    func testValidatorRejectsShortcutAlreadyOwnedByAnotherHotkey() {
        let existing = ContextualHotkey(
            name: "Research",
            keyCode: 31,
            modifiers: UInt(NSEvent.ModifierFlags.command.rawValue),
            otherSpacesAction: ContextualHotkeyAction(
                kind: .openOrActivate,
                appBundleIdentifier: "com.example.research",
                appName: "Research"
            )
        )
        let candidate = ContextualHotkey(
            name: "Writing",
            keyCode: 31,
            modifiers: UInt(NSEvent.ModifierFlags.command.rawValue),
            otherSpacesAction: ContextualHotkeyAction(
                kind: .openOrActivate,
                appBundleIdentifier: "com.example.notes",
                appName: "Notes"
            )
        )

        XCTAssertEqual(
            ContextualHotkeyValidator.validationError(for: candidate, existing: [existing]),
            .shortcutInUse("Research")
        )
    }

    func testValidatorRequiresShortcutModifierAndAtLeastOneAction() {
        var hotkey = ContextualHotkey(name: "Workspace", keyCode: 31, modifiers: 0)
        XCTAssertEqual(
            ContextualHotkeyValidator.validationError(for: hotkey, existing: []),
            .missingModifier
        )

        hotkey.modifiers = UInt(NSEvent.ModifierFlags.command.rawValue)
        XCTAssertEqual(
            ContextualHotkeyValidator.validationError(for: hotkey, existing: []),
            .missingAction
        )

        hotkey.otherSpacesAction = ContextualHotkeyAction(
            kind: .openOrActivate,
            appBundleIdentifier: "com.example.notes",
            appName: "Notes"
        )
        XCTAssertNil(ContextualHotkeyValidator.validationError(for: hotkey, existing: []))
    }

    func testDuplicateCopiesMappingsButClearsShortcutAndStartsDisabled() {
        let mapping = ContextualHotkeySpaceAction(
            spaceID: "research-space",
            action: ContextualHotkeyAction(
                kind: .openOrActivate,
                appBundleIdentifier: "com.example.research",
                appName: "Research"
            )
        )
        let original = ContextualHotkey(
            name: "Workspace",
            keyCode: 31,
            modifiers: UInt(NSEvent.ModifierFlags.command.rawValue),
            spaceActions: [mapping]
        )

        let duplicate = original.duplicate()

        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertEqual(duplicate.spaceActions, original.spaceActions)
        XCTAssertNil(duplicate.keyCode)
        XCTAssertFalse(duplicate.isEnabled)
    }
}

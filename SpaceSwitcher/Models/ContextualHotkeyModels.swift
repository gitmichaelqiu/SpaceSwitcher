import AppKit
import Carbon.HIToolbox
import Foundation

enum ContextualHotkeyActionKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case doNothing
    case openOrActivate
    case activateIfRunning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doNothing: NSLocalizedString("Do nothing", comment: "Contextual hotkey action")
        case .openOrActivate: NSLocalizedString("Open or activate app", comment: "Contextual hotkey action")
        case .activateIfRunning: NSLocalizedString("Activate only if running", comment: "Contextual hotkey action")
        }
    }

    var symbolName: String {
        switch self {
        case .doNothing: "minus.circle"
        case .openOrActivate: "arrow.up.forward.app"
        case .activateIfRunning: "macwindow.on.rectangle"
        }
    }
}

struct ContextualHotkeyAction: Codable, Equatable, Hashable {
    var kind: ContextualHotkeyActionKind
    var appBundleIdentifier: String?
    var appName: String?

    init(
        kind: ContextualHotkeyActionKind = .doNothing,
        appBundleIdentifier: String? = nil,
        appName: String? = nil
    ) {
        self.kind = kind
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
    }

    static let doNothing = Self()

    var isConfigured: Bool {
        kind == .doNothing || !(appBundleIdentifier?.isEmpty ?? true)
    }

    var isAction: Bool {
        kind != .doNothing
    }
}

struct ContextualHotkeySpaceAction: Codable, Equatable, Hashable, Identifiable {
    var spaceID: String
    var action: ContextualHotkeyAction

    var id: String { spaceID }
}

struct ContextualHotkey: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var keyCode: Int?
    var modifiers: UInt
    var isEnabled: Bool
    var spaceActions: [ContextualHotkeySpaceAction]
    var otherSpacesAction: ContextualHotkeyAction

    init(
        id: UUID = UUID(),
        name: String = "Open Workspace App",
        keyCode: Int? = nil,
        modifiers: UInt = 0,
        isEnabled: Bool = true,
        spaceActions: [ContextualHotkeySpaceAction] = [],
        otherSpacesAction: ContextualHotkeyAction = .doNothing
    ) {
        self.id = id
        self.name = name
        self.keyCode = keyCode
        self.modifiers = ContextualHotkeyModifiers.normalized(modifiers)
        self.isEnabled = isEnabled
        self.spaceActions = spaceActions
        self.otherSpacesAction = otherSpacesAction
    }

    func action(for spaceID: String) -> ContextualHotkeyAction {
        spaceActions.first(where: { $0.spaceID == spaceID })?.action ?? otherSpacesAction
    }

    var shortcutDescription: String {
        guard let keyCode else {
            return NSLocalizedString("No shortcut set", comment: "Contextual hotkey without a recorded shortcut")
        }
        return ShortcutHelper.format(code: keyCode, modifiers: modifiers)
    }

    var configuredSpaceCount: Int {
        spaceActions.count
    }

    func duplicate(named name: String? = nil) -> Self {
        Self(
            name: name ?? String(format: NSLocalizedString("%@ Copy", comment: "Name for a duplicated contextual hotkey"), self.name),
            keyCode: nil,
            modifiers: 0,
            isEnabled: false,
            spaceActions: spaceActions,
            otherSpacesAction: otherSpacesAction
        )
    }
}

enum ContextualHotkeyModifiers {
    static let supportedFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    static let supportedMask = UInt(supportedFlags.rawValue)

    static func normalized(_ modifiers: UInt) -> UInt {
        modifiers & supportedMask
    }

    static func containsModifier(_ modifiers: UInt) -> Bool {
        normalized(modifiers) != 0
    }

    static func carbonFlags(from modifiers: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: normalized(modifiers))
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        return carbonFlags
    }
}

enum ContextualHotkeyValidationError: Equatable {
    case missingName
    case missingShortcut
    case missingModifier
    case shortcutInUse(String)
    case missingAction
    case missingApplication

    var message: String {
        switch self {
        case .missingName:
            NSLocalizedString("Enter a name for this hotkey.", comment: "Contextual hotkey validation")
        case .missingShortcut:
            NSLocalizedString("Record a shortcut before enabling this hotkey.", comment: "Contextual hotkey validation")
        case .missingModifier:
            NSLocalizedString("Include at least one modifier key, such as Command or Option.", comment: "Contextual hotkey validation")
        case .shortcutInUse(let name):
            String(
                format: NSLocalizedString("This shortcut is already used by %@. Choose another.", comment: "Contextual hotkey conflict"),
                name
            )
        case .missingAction:
            NSLocalizedString("Choose at least one action for a Space or Other Spaces.", comment: "Contextual hotkey validation")
        case .missingApplication:
            NSLocalizedString("Choose an application for each app action.", comment: "Contextual hotkey validation")
        }
    }
}

enum ContextualHotkeyValidator {
    static func validationError(
        for candidate: ContextualHotkey,
        existing: [ContextualHotkey]
    ) -> ContextualHotkeyValidationError? {
        guard !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingName
        }

        if candidate.isEnabled, candidate.keyCode == nil {
            return .missingShortcut
        }

        if let keyCode = candidate.keyCode {
            guard ContextualHotkeyModifiers.containsModifier(candidate.modifiers) else {
                return .missingModifier
            }

            if let conflict = existing.first(where: {
                $0.id != candidate.id
                    && $0.keyCode == keyCode
                    && ContextualHotkeyModifiers.normalized($0.modifiers)
                        == ContextualHotkeyModifiers.normalized(candidate.modifiers)
            }) {
                return .shortcutInUse(conflict.name)
            }
        }

        let actions = candidate.spaceActions.map(\.action) + [candidate.otherSpacesAction]
        guard actions.contains(where: \.isAction) else {
            return .missingAction
        }
        guard actions.allSatisfy(\.isConfigured) else {
            return .missingApplication
        }
        return nil
    }
}

enum ContextualHotkeySpaceResolver {
    static func action(
        for hotkey: ContextualHotkey,
        currentSpaceID: String?,
        knownSpaceIDs: Set<String>,
        apiIsAvailable: Bool,
        hotkeysAreEnabled: Bool
    ) -> ContextualHotkeyAction? {
        guard hotkeysAreEnabled,
              hotkey.isEnabled,
              apiIsAvailable,
              let currentSpaceID,
              knownSpaceIDs.contains(currentSpaceID) else {
            return nil
        }
        return hotkey.action(for: currentSpaceID)
    }
}

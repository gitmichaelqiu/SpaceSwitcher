import AppKit
import Carbon.HIToolbox
import Foundation

enum ContextualHotkeyActionKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case doNothing
    case openOrActivate
    case activateIfRunning
    case hideApp
    case unhideApp
    case toggleAppVisibility
    case minimizeWindows
    case unminimizeWindows
    case toggleWindowMinimization

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doNothing: NSLocalizedString("Do nothing", comment: "Contextual hotkey action")
        case .openOrActivate: NSLocalizedString("Open or activate app", comment: "Contextual hotkey action")
        case .activateIfRunning: NSLocalizedString("Activate only if running", comment: "Contextual hotkey action")
        case .hideApp: NSLocalizedString("Hide app", comment: "Contextual hotkey action")
        case .unhideApp: NSLocalizedString("Unhide app", comment: "Contextual hotkey action")
        case .toggleAppVisibility: NSLocalizedString("Toggle app visibility", comment: "Contextual hotkey action")
        case .minimizeWindows: NSLocalizedString("Minimize windows", comment: "Contextual hotkey action")
        case .unminimizeWindows: NSLocalizedString("Unminimize windows", comment: "Contextual hotkey action")
        case .toggleWindowMinimization: NSLocalizedString("Toggle window minimization", comment: "Contextual hotkey action")
        }
    }

    var requiresAccessibility: Bool {
        switch self {
        case .minimizeWindows, .unminimizeWindows, .toggleWindowMinimization:
            true
        default:
            false
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

struct ContextualHotkeySpaceActionGroup: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var spaceIDs: Set<String>
    var action: ContextualHotkeyAction

    init(
        id: UUID = UUID(),
        spaceIDs: Set<String>,
        action: ContextualHotkeyAction = .doNothing
    ) {
        self.id = id
        self.spaceIDs = spaceIDs
        self.action = action
    }
}

struct ContextualHotkey: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var keyCode: Int?
    var modifiers: UInt
    var isEnabled: Bool
    var spaceActionGroups: [ContextualHotkeySpaceActionGroup]
    var otherSpacesAction: ContextualHotkeyAction

    init(
        id: UUID = UUID(),
        name: String = "",
        keyCode: Int? = nil,
        modifiers: UInt = 0,
        isEnabled: Bool = true,
        spaceActionGroups: [ContextualHotkeySpaceActionGroup] = [],
        otherSpacesAction: ContextualHotkeyAction = .doNothing
    ) {
        self.id = id
        self.name = name
        self.keyCode = keyCode
        self.modifiers = ContextualHotkeyModifiers.normalized(modifiers)
        self.isEnabled = isEnabled
        self.spaceActionGroups = spaceActionGroups
        self.otherSpacesAction = otherSpacesAction
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        keyCode: Int? = nil,
        modifiers: UInt = 0,
        isEnabled: Bool = true,
        spaceActions: [ContextualHotkeySpaceAction],
        otherSpacesAction: ContextualHotkeyAction = .doNothing
    ) {
        self.init(
            id: id,
            name: name,
            keyCode: keyCode,
            modifiers: modifiers,
            isEnabled: isEnabled,
            spaceActionGroups: Self.groupedSpaceActions(spaceActions),
            otherSpacesAction: otherSpacesAction
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, keyCode, modifiers, isEnabled, spaceActionGroups, spaceActions, otherSpacesAction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        keyCode = try container.decodeIfPresent(Int.self, forKey: .keyCode)
        modifiers = ContextualHotkeyModifiers.normalized(
            try container.decodeIfPresent(UInt.self, forKey: .modifiers) ?? 0
        )
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        otherSpacesAction = try container.decodeIfPresent(
            ContextualHotkeyAction.self,
            forKey: .otherSpacesAction
        ) ?? .doNothing

        if let groups = try container.decodeIfPresent(
            [ContextualHotkeySpaceActionGroup].self,
            forKey: .spaceActionGroups
        ) {
            spaceActionGroups = groups
        } else {
            let legacyActions = try container.decodeIfPresent(
                [ContextualHotkeySpaceAction].self,
                forKey: .spaceActions
            ) ?? []
            spaceActionGroups = Self.groupedSpaceActions(legacyActions)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(spaceActionGroups, forKey: .spaceActionGroups)
        // Keep a flattened representation for older app versions.
        try container.encode(spaceActions, forKey: .spaceActions)
        try container.encode(otherSpacesAction, forKey: .otherSpacesAction)
    }

    var spaceActions: [ContextualHotkeySpaceAction] {
        spaceActionGroups.flatMap { group in
            group.spaceIDs.sorted().map { spaceID in
                ContextualHotkeySpaceAction(spaceID: spaceID, action: group.action)
            }
        }
    }

    func action(for spaceID: String) -> ContextualHotkeyAction {
        spaceActionGroups.first(where: { $0.spaceIDs.contains(spaceID) })?.action ?? otherSpacesAction
    }

    var requiresAccessibility: Bool {
        (spaceActionGroups.map(\.action) + [otherSpacesAction])
            .contains { $0.kind.requiresAccessibility }
    }

    var shortcutDescription: String {
        guard let keyCode else {
            return NSLocalizedString("No shortcut set", comment: "Contextual hotkey without a recorded shortcut")
        }
        return ShortcutHelper.format(code: keyCode, modifiers: modifiers)
    }

    func duplicate(named name: String? = nil) -> Self {
        Self(
            name: name ?? String(format: NSLocalizedString("%@ Copy", comment: "Name for a duplicated contextual hotkey"), self.name),
            keyCode: nil,
            modifiers: 0,
            isEnabled: false,
            spaceActionGroups: spaceActionGroups.map {
                ContextualHotkeySpaceActionGroup(spaceIDs: $0.spaceIDs, action: $0.action)
            },
            otherSpacesAction: otherSpacesAction
        )
    }

    private static func groupedSpaceActions(
        _ actions: [ContextualHotkeySpaceAction]
    ) -> [ContextualHotkeySpaceActionGroup] {
        var groups: [ContextualHotkeySpaceActionGroup] = []
        var assignedSpaceIDs = Set<String>()

        for mapping in actions where assignedSpaceIDs.insert(mapping.spaceID).inserted {
            if let groupIndex = groups.firstIndex(where: { $0.action == mapping.action }) {
                groups[groupIndex].spaceIDs.insert(mapping.spaceID)
            } else {
                groups.append(
                    ContextualHotkeySpaceActionGroup(
                        spaceIDs: [mapping.spaceID],
                        action: mapping.action
                    )
                )
            }
        }
        return groups
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
    case emptySpaceGroup
    case duplicateSpaceGroups
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
        case .emptySpaceGroup:
            NSLocalizedString("Every space group must include at least one Space.", comment: "Contextual hotkey validation")
        case .duplicateSpaceGroups:
            NSLocalizedString("Each Space can belong to only one group.", comment: "Contextual hotkey validation")
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

        if candidate.spaceActionGroups.contains(where: { $0.spaceIDs.isEmpty }) {
            return .emptySpaceGroup
        }

        let assignedSpaceIDs = candidate.spaceActionGroups.flatMap { Array($0.spaceIDs) }
        if Set(assignedSpaceIDs).count != assignedSpaceIDs.count {
            return .duplicateSpaceGroups
        }

        let actions = candidate.spaceActionGroups.map(\.action) + [candidate.otherSpacesAction]
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

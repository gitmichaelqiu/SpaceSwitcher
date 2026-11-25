import Foundation

struct ImportedSettings {
    let rules: [AppRule]?
    let hotkeys: [ContextualHotkey]?
}

private struct SettingsTransferArchive: Codable {
    let formatVersion: Int
    let rules: [AppRule]
    let hotkeys: [ContextualHotkey]
}

enum SettingsTransferService {
    private static let currentFormatVersion = 1

    static func encode(rules: [AppRule], hotkeys: [ContextualHotkey]) throws -> Data {
        let archive = SettingsTransferArchive(
            formatVersion: currentFormatVersion,
            rules: rules,
            hotkeys: hotkeys
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> ImportedSettings {
        let decoder = JSONDecoder()

        if let archive = try? decoder.decode(SettingsTransferArchive.self, from: data) {
            guard archive.formatVersion == currentFormatVersion else {
                throw SettingsTransferError.unsupportedVersion(archive.formatVersion)
            }
            guard !archive.rules.isEmpty || !archive.hotkeys.isEmpty else {
                throw SettingsTransferError.emptyArchive
            }
            return ImportedSettings(rules: archive.rules, hotkeys: archive.hotkeys)
        }

        // Earlier releases exported a bare array of rules. Continue importing
        // those files without changing the user's existing hotkeys.
        return ImportedSettings(
            rules: try RuleTransferService.decode(data),
            hotkeys: nil
        )
    }

    static func applying(
        _ importedHotkeys: [ContextualHotkey],
        to existingHotkeys: [ContextualHotkey],
        strategy: RuleImportStrategy
    ) -> [ContextualHotkey] {
        let result: [ContextualHotkey]

        switch strategy {
        case .replaceAll:
            result = importedHotkeys

        case .keepAll:
            result = existingHotkeys + importedHotkeys

        case .addNewApps:
            var additions: [ContextualHotkey] = []
            for hotkey in importedHotkeys {
                guard !existingHotkeys.contains(where: { matches($0, hotkey) }),
                      !additions.contains(where: { matches($0, hotkey) }) else {
                    continue
                }
                additions.append(hotkey)
            }
            result = existingHotkeys + additions

        case .replaceMatchingApps:
            var replacements = existingHotkeys
            for hotkey in importedHotkeys {
                if let index = replacements.firstIndex(where: { matches($0, hotkey) }) {
                    replacements[index] = hotkey
                } else {
                    replacements.append(hotkey)
                }
            }
            result = replacements
        }

        return ensuringUniqueHotkeyIDs(in: result)
    }

    private static func matches(_ lhs: ContextualHotkey, _ rhs: ContextualHotkey) -> Bool {
        if lhs.id == rhs.id {
            return true
        }
        guard let lhsKeyCode = lhs.keyCode,
              let rhsKeyCode = rhs.keyCode else {
            return false
        }
        return lhsKeyCode == rhsKeyCode
            && ContextualHotkeyModifiers.normalized(lhs.modifiers)
                == ContextualHotkeyModifiers.normalized(rhs.modifiers)
    }

    private static func ensuringUniqueHotkeyIDs(
        in hotkeys: [ContextualHotkey]
    ) -> [ContextualHotkey] {
        var usedIDs = Set<UUID>()
        return hotkeys.map { hotkey in
            var uniqueHotkey = hotkey
            while usedIDs.contains(uniqueHotkey.id) {
                uniqueHotkey.id = UUID()
            }
            usedIDs.insert(uniqueHotkey.id)
            return uniqueHotkey
        }
    }
}

enum SettingsTransferError: LocalizedError, Equatable {
    case emptyArchive
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .emptyArchive:
            NSLocalizedString(
                "The selected file does not contain any rules or hotkeys.",
                comment: "Error shown when importing an empty settings file"
            )
        case .unsupportedVersion(let version):
            String(
                format: NSLocalizedString(
                    "This settings file uses an unsupported format version (%d).",
                    comment: "Error shown when importing a newer settings file"
                ),
                version
            )
        }
    }
}

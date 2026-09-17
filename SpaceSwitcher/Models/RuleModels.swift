import Foundation
import AppKit

// MARK: - Actions
enum RuleCondition: String, CaseIterable, Codable, Hashable, Identifiable {
    case windowMinimized
    case windowFrontmost
    case applicationActive
    case applicationHidden
    case windowFullscreen

    var id: String { rawValue }

    var localizedString: String {
        switch self {
        case .windowMinimized:
            return NSLocalizedString("Window is minimized", comment: "Condition matching minimized windows")
        case .windowFrontmost:
            return NSLocalizedString("Window is frontmost", comment: "Condition matching the frontmost window")
        case .applicationActive:
            return NSLocalizedString("Application is active", comment: "Condition matching active applications")
        case .applicationHidden:
            return NSLocalizedString("Application is hidden", comment: "Condition matching hidden applications")
        case .windowFullscreen:
            return NSLocalizedString("Window is fullscreen", comment: "Condition matching fullscreen windows")
        }
    }
}

enum WindowAction: Identifiable, Codable, Equatable, Hashable {
    case show
    case restore
    case hide
    case minimize
    case bringToFront
    case ifCondition(RuleCondition)
    case endIf
    // Standard App-Specific Hotkey
    case hotkey(keyCode: Int, modifiers: UInt, restoreWindow: Bool, waitFrontmost: Bool)
    // NEW: Global System Hotkey
    case globalHotkey(keyCode: Int, modifiers: UInt)
    
    var id: String {
        switch self {
        case .show: return "show"
        case .restore: return "restore"
        case .hide: return "hide"
        case .minimize: return "minimize"
        case .bringToFront: return "bringToFront"
        case .ifCondition(let condition): return "if-\(condition.rawValue)"
        case .endIf: return "endIf"
        case .hotkey(let k, let m, _, _): return "hotkey-\(k)-\(m)"
        case .globalHotkey(let k, let m): return "global-\(k)-\(m)"
        }
    }
    
    var localizedString: String {
        switch self {
        case .show: return NSLocalizedString("Show", comment: "")
        case .restore: return NSLocalizedString("Restore", comment: "")
        case .hide: return NSLocalizedString("Hide", comment: "")
        case .minimize: return NSLocalizedString("Minimize", comment: "")
        case .bringToFront: return NSLocalizedString("Bring to Front", comment: "")
        case .ifCondition(let condition):
            return String(
                format: NSLocalizedString("If %@", comment: "Conditional rule action"),
                condition.localizedString
            )
        case .endIf:
            return NSLocalizedString("End If", comment: "End of a conditional rule action block")
        case .hotkey(let code, let mods, _, _):
            return NSLocalizedString("App Shortcut", comment: "") + ": " + ShortcutHelper.format(code: code, modifiers: mods)
        case .globalHotkey(let code, let mods):
            return NSLocalizedString("System Shortcut", comment: "") + ": " + ShortcutHelper.format(code: code, modifiers: mods)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, condition, keyCode, modifiers, restoreWindow, waitFrontmost
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "show": self = .show
        case "restore": self = .restore
        case "hide": self = .hide
        case "minimize": self = .minimize
        case "bringToFront": self = .bringToFront
        case "if":
            let condition = try container.decode(RuleCondition.self, forKey: .condition)
            self = .ifCondition(condition)
        case "endIf": self = .endIf
        case "hotkey":
            let c = try container.decode(Int.self, forKey: .keyCode)
            let m = try container.decode(UInt.self, forKey: .modifiers)
            let r = try container.decodeIfPresent(Bool.self, forKey: .restoreWindow) ?? false
            let w = try container.decodeIfPresent(Bool.self, forKey: .waitFrontmost) ?? true
            self = .hotkey(keyCode: c, modifiers: m, restoreWindow: r, waitFrontmost: w)
        case "globalHotkey":
            let c = try container.decode(Int.self, forKey: .keyCode)
            let m = try container.decode(UInt.self, forKey: .modifiers)
            self = .globalHotkey(keyCode: c, modifiers: m)
        default: self = .show
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .show: try container.encode("show", forKey: .type)
        case .restore: try container.encode("restore", forKey: .type)
        case .hide: try container.encode("hide", forKey: .type)
        case .minimize: try container.encode("minimize", forKey: .type)
        case .bringToFront: try container.encode("bringToFront", forKey: .type)
        case .ifCondition(let condition):
            try container.encode("if", forKey: .type)
            try container.encode(condition, forKey: .condition)
        case .endIf: try container.encode("endIf", forKey: .type)
        case .hotkey(let c, let m, let r, let w):
            try container.encode("hotkey", forKey: .type)
            try container.encode(c, forKey: .keyCode)
            try container.encode(m, forKey: .modifiers)
            try container.encode(r, forKey: .restoreWindow)
            try container.encode(w, forKey: .waitFrontmost)
        case .globalHotkey(let c, let m):
            try container.encode("globalHotkey", forKey: .type)
            try container.encode(c, forKey: .keyCode)
            try container.encode(m, forKey: .modifiers)
        }
    }
}

private enum LegacyWindowCondition: String, Codable {
    case none
    case minimized
}

// MARK: - Action Wrapper
struct ActionItem: Identifiable, Codable, Hashable {
    let id = UUID()
    var value: WindowAction
    
    init(_ value: WindowAction) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(WindowAction.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Shortcut Helper (Updated for Reverse Lookup)
enum ShortcutHelper {
    static func format(code: Int, modifiers: UInt) -> String {
        if code == -1 { return "None" }
        var string = ""
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { string += "⌃" }
        if flags.contains(.option)  { string += "⌥" }
        if flags.contains(.shift)   { string += "⇧" }
        if flags.contains(.command) { string += "⌘" }
        
        if let char = keyString(for: code) {
            string += char.uppercased()
        } else {
            string += "?"
        }
        return string
    }
    
    // KeyCode -> String
    static func keyString(for code: Int) -> String? {
        switch code {
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"; case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"; case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"; case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"; case 17: return "T"; case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"; case 22: return "6"; case 23: return "5"; case 24: return "="; case 25: return "9"; case 26: return "7"; case 27: return "-"; case 28: return "8"; case 29: return "0"; case 30: return "]"; case 31: return "O"; case 32: return "U"; case 33: return "["; case 34: return "I"; case 35: return "P"; case 36: return "⏎"; case 37: return "L"; case 38: return "J"; case 39: return "'"; case 40: return "K"; case 41: return ";"; case 42: return "\\"; case 43: return ","; case 44: return "/"; case 45: return "N"; case 46: return "M"; case 47: return "."; case 48: return "Tab"; case 49: return "Space"; case 50: return "`"; case 51: return "Del"; case 53: return "Esc";
        // Arrows
        case 123: return "←"; case 124: return "→"; case 125: return "↓"; case 126: return "↑"
        // F-Keys
        case 122: return "F1"; case 120: return "F2"; case 99: return "F3"; case 118: return "F4"; case 96: return "F5"; case 97: return "F6"; case 98: return "F7"; case 100: return "F8"; case 101: return "F9"; case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
        // Others
        case 115: return "Home"; case 119: return "End"; case 116: return "PgUp"; case 121: return "PgDn"
        case 71: return "Clr"; case 76: return "Ent"
        default: return nil
        }
    }
    
    // String -> KeyCode (For Global Hotkey Textbox)
    static func keyCode(for char: String) -> Int {
        let upper = char.uppercased()
        for code in 0...255 {
            if keyString(for: code)?.uppercased() == upper {
                return code
            }
        }
        return -1 // Not found
    }
}

struct RuleGroup: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var targetSpaceIDs: Set<String>
    var usesSourceSpace: Bool = false
    var actions: [ActionItem]

    init(
        targetSpaceIDs: Set<String>,
        actions: [ActionItem],
        usesSourceSpace: Bool = false
    ) {
        self.targetSpaceIDs = targetSpaceIDs
        self.actions = actions
        self.usesSourceSpace = usesSourceSpace
    }

    private enum CodingKeys: String, CodingKey {
        case id, targetSpaceIDs, usesSourceSpace, sourceSpaceID, windowCondition, actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        targetSpaceIDs = try container.decode(Set<String>.self, forKey: .targetSpaceIDs)
        actions = try container.decode([ActionItem].self, forKey: .actions)

        // Migrate the short-lived sourceSpaceID representation to the
        // source-space condition. The old value identified a space to filter;
        // the new model intentionally stores only whether the condition is on.
        if let value = try container.decodeIfPresent(Bool.self, forKey: .usesSourceSpace) {
            usesSourceSpace = value
        } else {
            usesSourceSpace = try container.decodeIfPresent(String.self, forKey: .sourceSpaceID) != nil
        }

        // Older versions stored a single group-level minimized condition. Keep
        // decoding that key so existing rules retain their behavior while the
        // in-memory model uses the flat conditional action representation.
        if try container.decodeIfPresent(LegacyWindowCondition.self, forKey: .windowCondition) == .minimized {
            actions.insert(ActionItem(.ifCondition(.windowMinimized)), at: 0)
            actions.append(ActionItem(.endIf))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(targetSpaceIDs, forKey: .targetSpaceIDs)
        try container.encode(usesSourceSpace, forKey: .usesSourceSpace)
        try container.encode(actions, forKey: .actions)
    }
}

struct AppRule: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var appBundleID: String
    var appName: String
    var appliesToAllApps: Bool = false
    var groups: [RuleGroup]
    var elseActions: [ActionItem]
    var isEnabled: Bool = true
    
    init(
        appBundleID: String,
        appName: String,
        appliesToAllApps: Bool = false,
        groups: [RuleGroup],
        elseActions: [ActionItem],
        isEnabled: Bool = true
    ) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.appliesToAllApps = appliesToAllApps
        self.groups = groups
        self.elseActions = elseActions
        self.isEnabled = isEnabled
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appBundleID = try container.decodeIfPresent(String.self, forKey: .appBundleID) ?? ""
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? ""
        appliesToAllApps = try container.decodeIfPresent(Bool.self, forKey: .appliesToAllApps) ?? false
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        
        if let g = try? container.decode([RuleGroup].self, forKey: .groups) { groups = g } else { groups = [] }
        if let arr = try? container.decode([ActionItem].self, forKey: .elseActions) { elseActions = arr } else { elseActions = [] }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, appBundleID, appName, appliesToAllApps, isEnabled, groups, elseActions
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appBundleID, forKey: .appBundleID)
        try container.encode(appName, forKey: .appName)
        try container.encode(appliesToAllApps, forKey: .appliesToAllApps)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(groups, forKey: .groups)
        try container.encode(elseActions, forKey: .elseActions)
    }
}

struct SpaceInfo: Identifiable, Codable, Hashable {
    let id: String; let name: String; let number: Int
    static func == (lhs: SpaceInfo, rhs: SpaceInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

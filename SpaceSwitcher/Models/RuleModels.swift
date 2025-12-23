import Foundation
import AppKit

// MARK: - Actions
enum WindowAction: Identifiable, Codable, Equatable, Hashable {
    case show
    case hide
    case minimize
    case bringToFront
    // UPDATED: Added configuration flags
    case hotkey(keyCode: Int, modifiers: UInt, restoreWindow: Bool, waitFrontmost: Bool)
    
    var id: String {
        switch self {
        case .show: return "show"
        case .hide: return "hide"
        case .minimize: return "minimize"
        case .bringToFront: return "bringToFront"
        case .hotkey(let k, let m, _, _): return "hotkey-\(k)-\(m)"
        }
    }
    
    var localizedString: String {
        switch self {
        case .show: return NSLocalizedString("Show", comment: "")
        case .hide: return NSLocalizedString("Hide", comment: "")
        case .minimize: return NSLocalizedString("Minimize", comment: "")
        case .bringToFront: return NSLocalizedString("Bring to Front", comment: "")
        case .hotkey(let code, let mods, _, _):
            return "Press: " + ShortcutHelper.format(code: code, modifiers: mods)
        }
    }

    // Custom Codable implementation
    private enum CodingKeys: String, CodingKey { case type, keyCode, modifiers, restoreWindow, waitFrontmost }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "show": self = .show
        case "hide": self = .hide
        case "minimize": self = .minimize
        case "bringToFront": self = .bringToFront
        case "hotkey":
            let c = try container.decode(Int.self, forKey: .keyCode)
            let m = try container.decode(UInt.self, forKey: .modifiers)
            // Default values for backward compatibility
            let r = try container.decodeIfPresent(Bool.self, forKey: .restoreWindow) ?? false
            let w = try container.decodeIfPresent(Bool.self, forKey: .waitFrontmost) ?? true
            self = .hotkey(keyCode: c, modifiers: m, restoreWindow: r, waitFrontmost: w)
        default: self = .show
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .show: try container.encode("show", forKey: .type)
        case .hide: try container.encode("hide", forKey: .type)
        case .minimize: try container.encode("minimize", forKey: .type)
        case .bringToFront: try container.encode("bringToFront", forKey: .type)
        case .hotkey(let c, let m, let r, let w):
            try container.encode("hotkey", forKey: .type)
            try container.encode(c, forKey: .keyCode)
            try container.encode(m, forKey: .modifiers)
            try container.encode(r, forKey: .restoreWindow)
            try container.encode(w, forKey: .waitFrontmost)
        }
    }
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

// MARK: - Shortcut Helper (Same as before)
enum ShortcutHelper {
    static func format(code: Int, modifiers: UInt) -> String {
        if code == -1 { return "Record Shortcut..." }
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
    
    static func keyString(for code: Int) -> String? {
        switch code {
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"; case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"; case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"; case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"; case 17: return "T"; case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"; case 22: return "6"; case 23: return "5"; case 24: return "="; case 25: return "9"; case 26: return "7"; case 27: return "-"; case 28: return "8"; case 29: return "0"; case 30: return "]"; case 31: return "O"; case 32: return "U"; case 33: return "["; case 34: return "I"; case 35: return "P"; case 36: return "⏎"; case 37: return "L"; case 38: return "J"; case 39: return "'"; case 40: return "K"; case 41: return ";"; case 42: return "\\"; case 43: return ","; case 44: return "/"; case 45: return "N"; case 46: return "M"; case 47: return "."; case 48: return "Tab"; case 49: return "Space"; case 50: return "`"; case 51: return "Del"; case 53: return "Esc";
        default: return nil
        }
    }
}

struct RuleGroup: Identifiable, Codable {
    var id: UUID = UUID()
    var targetSpaceIDs: Set<String>
    var actions: [ActionItem]
}

struct AppRule: Identifiable, Codable {
    var id: UUID = UUID()
    var appBundleID: String
    var appName: String
    var groups: [RuleGroup]
    var elseActions: [ActionItem]
    var isEnabled: Bool = true
    
    init(appBundleID: String, appName: String, groups: [RuleGroup], elseActions: [ActionItem], isEnabled: Bool = true) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.groups = groups
        self.elseActions = elseActions
        self.isEnabled = isEnabled
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appBundleID = try container.decode(String.self, forKey: .appBundleID)
        appName = try container.decode(String.self, forKey: .appName)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        
        if let g = try? container.decode([RuleGroup].self, forKey: .groups) {
            groups = g
        } else {
            let oldSpaces = try? container.decode(Set<String>.self, forKey: .targetSpaceIDs)
            var oldMatch: [ActionItem] = []
            if let arr = try? container.decode([ActionItem].self, forKey: .matchActions) { oldMatch = arr }
            else if let s = try? container.decode(WindowAction.self, forKey: .matchAction) { oldMatch = [ActionItem(s)] }
            else { oldMatch = [ActionItem(.show)] }
            
            if let spaces = oldSpaces, !spaces.isEmpty {
                groups = [RuleGroup(targetSpaceIDs: spaces, actions: oldMatch)]
            } else {
                groups = []
            }
        }
        
        if let arr = try? container.decode([ActionItem].self, forKey: .elseActions) {
            elseActions = arr
        } else if let s = try? container.decode(WindowAction.self, forKey: .elseAction) {
            elseActions = [ActionItem(s)]
        } else {
            elseActions = [ActionItem(.hide)]
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, appBundleID, appName, isEnabled
        case groups, elseActions, elseAction
        case targetSpaceIDs, matchActions, matchAction
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appBundleID, forKey: .appBundleID)
        try container.encode(appName, forKey: .appName)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(groups, forKey: .groups)
        try container.encode(elseActions, forKey: .elseActions)
    }
}

struct SpaceInfo: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let number: Int
    static func == (lhs: SpaceInfo, rhs: SpaceInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

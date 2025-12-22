import Foundation

// MARK: - Actions
enum WindowAction: Identifiable, Codable, Equatable, Hashable {
    case show
    case hide
    case minimize
    case bringToFront
    case hotkey(keyCode: Int, modifiers: UInt)
    
    var id: String {
        switch self {
        case .show: return "show"
        case .hide: return "hide"
        case .minimize: return "minimize"
        case .bringToFront: return "bringToFront"
        case .hotkey(let k, let m): return "hotkey-\(k)-\(m)"
        }
    }
    
    var localizedString: String {
        switch self {
        case .show: return NSLocalizedString("Show", comment: "")
        case .hide: return NSLocalizedString("Hide", comment: "")
        case .minimize: return NSLocalizedString("Minimize", comment: "")
        case .bringToFront: return NSLocalizedString("Bring to Front", comment: "")
        case .hotkey(let code, let mods):
            return "Press: " + ShortcutHelper.format(code: code, modifiers: mods)
        }
    }

    // Custom Codable implementation (Same as before)
    private enum CodingKeys: String, CodingKey { case type, keyCode, modifiers }
    
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
            self = .hotkey(keyCode: c, modifiers: m)
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
        case .hotkey(let c, let m):
            try container.encode("hotkey", forKey: .type)
            try container.encode(c, forKey: .keyCode)
            try container.encode(m, forKey: .modifiers)
        }
    }
}

// MARK: - Shortcut Helper (Same as before)
enum ShortcutHelper {
    static func format(code: Int, modifiers: UInt) -> String {
        if code == -1 { return "Record..." }
        // Simple mapping for demo
        return "Key \(code)"
    }
}

// MARK: - Rule Group (NEW)
struct RuleGroup: Identifiable, Codable {
    var id: UUID = UUID()
    var targetSpaceIDs: Set<String>
    var actions: [WindowAction]
}

// MARK: - App Rule (UPDATED)
struct AppRule: Identifiable, Codable {
    var id: UUID = UUID()
    var appBundleID: String
    var appName: String
    
    // New Structure: List of Groups + Fallback
    var groups: [RuleGroup]
    var elseActions: [WindowAction]
    
    var isEnabled: Bool = true
    
    init(appBundleID: String, appName: String, groups: [RuleGroup], elseActions: [WindowAction], isEnabled: Bool = true) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.groups = groups
        self.elseActions = elseActions
        self.isEnabled = isEnabled
    }
    
    // Migration Logic
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appBundleID = try container.decode(String.self, forKey: .appBundleID)
        appName = try container.decode(String.self, forKey: .appName)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        
        // Try decoding new structure
        if let g = try? container.decode([RuleGroup].self, forKey: .groups) {
            groups = g
        } else {
            // Migrating old structure: Create one group from old targetSpaceIDs
            let oldSpaces = try? container.decode(Set<String>.self, forKey: .targetSpaceIDs)
            
            // Handle old actions (could be array or single)
            var oldMatch: [WindowAction] = []
            if let arr = try? container.decode([WindowAction].self, forKey: .matchActions) { oldMatch = arr }
            else if let s = try? container.decode(WindowAction.self, forKey: .matchAction) { oldMatch = [s] }
            else { oldMatch = [.show] }
            
            // Create the migrated group
            if let spaces = oldSpaces, !spaces.isEmpty {
                groups = [RuleGroup(targetSpaceIDs: spaces, actions: oldMatch)]
            } else {
                groups = []
            }
        }
        
        // Else Actions
        if let arr = try? container.decode([WindowAction].self, forKey: .elseActions) {
            elseActions = arr
        } else if let s = try? container.decode(WindowAction.self, forKey: .elseAction) {
            elseActions = [s]
        } else {
            elseActions = [.hide]
        }
    }
    
    // Keys for both old and new to support migration reading
    enum CodingKeys: String, CodingKey {
        case id, appBundleID, appName, isEnabled
        case groups, elseActions, elseAction
        // Legacy keys
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
    
    static func == (lhs: SpaceInfo, rhs: SpaceInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

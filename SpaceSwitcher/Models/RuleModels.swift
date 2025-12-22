import Foundation

enum WindowAction: String, Codable, CaseIterable, Identifiable {
    case doNothing = "DoNothing"
    case show = "Show"
    case hide = "Hide"
    case minimize = "Minimize"
    case bringToFront = "BringToFront" // New Action
    
    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .doNothing: return NSLocalizedString("DoNothing", comment: "")
        case .show: return NSLocalizedString("Show", comment: "")
        case .hide: return NSLocalizedString("Hide", comment: "")
        case .minimize: return NSLocalizedString("Minimize", comment: "")
        case .bringToFront: return NSLocalizedString("Bring to Front", comment: "")
        }
    }
}

struct AppRule: Identifiable, Codable {
    var id: UUID = UUID()
    var appBundleID: String
    var appName: String
    var targetSpaceIDs: Set<String>
    
    // Changed to Arrays for Sequences
    var matchActions: [WindowAction]
    var elseActions: [WindowAction]
    
    var isEnabled: Bool = true
    
    // Default Init
    init(appBundleID: String, appName: String, targetSpaceIDs: Set<String>, matchActions: [WindowAction], elseActions: [WindowAction], isEnabled: Bool = true) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.targetSpaceIDs = targetSpaceIDs
        self.matchActions = matchActions
        self.elseActions = elseActions
        self.isEnabled = isEnabled
    }
    
    // Migration Logic: Handle old JSON with single 'matchAction'
    enum CodingKeys: String, CodingKey {
        case id, appBundleID, appName, targetSpaceIDs, isEnabled
        case matchActions, elseActions // New keys
        case matchAction, elseAction   // Old keys
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        appBundleID = try container.decode(String.self, forKey: .appBundleID)
        appName = try container.decode(String.self, forKey: .appName)
        targetSpaceIDs = try container.decode(Set<String>.self, forKey: .targetSpaceIDs)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        
        // Try decoding new arrays; fall back to wrapping old single values
        if let actions = try? container.decode([WindowAction].self, forKey: .matchActions) {
            matchActions = actions
        } else if let single = try? container.decode(WindowAction.self, forKey: .matchAction) {
            matchActions = [single]
        } else {
            matchActions = [.show] // Default
        }
        
        if let actions = try? container.decode([WindowAction].self, forKey: .elseActions) {
            elseActions = actions
        } else if let single = try? container.decode(WindowAction.self, forKey: .elseAction) {
            elseActions = [single]
        } else {
            elseActions = [.hide] // Default
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appBundleID, forKey: .appBundleID)
        try container.encode(appName, forKey: .appName)
        try container.encode(targetSpaceIDs, forKey: .targetSpaceIDs)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(matchActions, forKey: .matchActions)
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

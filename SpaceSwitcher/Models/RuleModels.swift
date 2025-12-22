import Foundation

enum WindowAction: String, Codable, CaseIterable, Identifiable {
    case doNothing = "DoNothing"
    case show = "Show"
    case hide = "Hide"
    case minimize = "Minimize" // Now active
    
    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .doNothing:
            return NSLocalizedString("DoNothing", comment: "Action: Do Nothing")
        case .show:
            return NSLocalizedString("Show", comment: "Action: Show Window")
        case .hide:
            return NSLocalizedString("Hide", comment: "Action: Hide Window")
        case .minimize:
            return NSLocalizedString("Minimize", comment: "Action: Minimize Window")
        }
    }
}

struct AppRule: Identifiable, Codable {
    var id: UUID = UUID()
    var appBundleID: String
    var appName: String
    var targetSpaceIDs: Set<String>
    
    var matchAction: WindowAction
    var elseAction: WindowAction
    
    var isEnabled: Bool = true
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

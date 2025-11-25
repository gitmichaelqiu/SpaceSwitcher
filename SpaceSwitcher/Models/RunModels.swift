import Foundation

enum WindowAction: String, Codable, CaseIterable, Identifiable {
    case doNothing = "DoNothing"
    case show = "Show"
    case hide = "Hide"
    // case minimize = "Minimize" // Requires Accessibility Permissions, keeping simple for now or add later
    
    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .doNothing:
            return NSLocalizedString("DoNothing", comment: "")
        case .show:
            return NSLocalizedString("Show", comment: "")
        case .hide:
            return NSLocalizedString("Hide", comment: "")
        }
    }
}

struct AppRule: Identifiable, Codable {
    var id: UUID = UUID()
    var appBundleID: String
    var appName: String
    var targetSpaceIDs: Set<String> // IDs from DesktopRenamer
    
    var matchAction: WindowAction
    var elseAction: WindowAction
    
    var isEnabled: Bool = true
}

struct RenamerSpace: Identifiable, Codable, Hashable {
    let id: String // UUID
    let name: String
    let number: Int
    
    // Conform to Hashable/Equatable for selection sets
    static func == (lhs: RenamerSpace, rhs: RenamerSpace) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

import Foundation

struct DockSet: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var dateCreated: Date
    // We store the raw plist array as Data (JSON encoded) to avoid type issues with [String: Any]
    let persistentAppsData: Data
    
    // Check if this set is essentially the "same" content-wise
    static func == (lhs: DockSet, rhs: DockSet) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

struct DockConfig: Codable {
    var dockSets: [DockSet] = []
    var defaultDockSetID: UUID?
    // Map Space UUID -> Dock Set UUID
    var spaceAssignments: [String: UUID] = [:]
}

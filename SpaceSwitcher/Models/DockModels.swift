import Foundation
import AppKit

// MARK: - Dock Tile Model
// Represents a single icon in the Dock (App, Folder, etc.)
struct DockTile: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var bundleIdentifier: String? // For apps
    var fileURL: URL?            // For apps or files
    
    // We store the raw dictionary for any keys we don't fully parse/edit,
    // ensuring we don't lose special system properties when saving back.
    var rawData: [String: Any]
    
    // Custom coding to handle the complex [String: Any] rawData
    enum CodingKeys: String, CodingKey {
        case id, label, bundleIdentifier, fileURL, rawData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        
        // Decode rawData as JSON Data then convert back to Dict (workaround for Any codable)
        let data = try container.decode(Data.self, forKey: .rawData)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        rawData = dict ?? [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(fileURL, forKey: .fileURL)
        
        // Encode rawData as Data
        let data = try JSONSerialization.data(withJSONObject: rawData)
        try container.encode(data, forKey: .rawData)
    }
    
    init(label: String, bundleIdentifier: String?, fileURL: URL?, rawData: [String: Any]) {
        self.label = label
        self.bundleIdentifier = bundleIdentifier
        self.fileURL = fileURL
        self.rawData = rawData
    }
    
    static func == (lhs: DockTile, rhs: DockTile) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Dock Set
struct DockSet: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var dateCreated: Date
    var tiles: [DockTile] // Now Editable
    
    static func == (lhs: DockSet, rhs: DockSet) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.tiles == rhs.tiles
    }
}

// MARK: - Config
struct DockConfig: Codable {
    var dockSets: [DockSet] = []
    var defaultDockSetID: UUID?
    var spaceAssignments: [String: UUID] = [:]
}

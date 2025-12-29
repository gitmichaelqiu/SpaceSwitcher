import Foundation
import AppKit

// MARK: - Dock Tile Model
struct DockTile: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var bundleIdentifier: String?
    var fileURL: URL?
    
    // We store the raw dictionary to preserve system data (aliases, folder settings, etc.)
    var rawData: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case id, label, bundleIdentifier, fileURL, rawData
    }
    
    // MARK: - Safe Serialization Fix
    // We use PropertyListSerialization because Dock data contains binary Data types (aliases)
    // which causes JSONSerialization to crash with "Invalid type in JSON write (__NSCFData)"
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        
        // 1. Decode the blob
        let data = try container.decode(Data.self, forKey: .rawData)
        
        // 2. Deserialize using PropertyList (Handles Data/Date types safely)
        var format = PropertyListSerialization.PropertyListFormat.binary
        if let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] {
            rawData = dict
        } else {
            rawData = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(fileURL, forKey: .fileURL)
        
        // 1. Serialize using PropertyList to support NSData/Date types
        let data = try PropertyListSerialization.data(fromPropertyList: rawData, format: .binary, options: 0)
        
        // 2. Encode the safe blob
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
    var tiles: [DockTile]
    
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

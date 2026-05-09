import Foundation

// MARK: - Dock Tile Model
struct DockTile: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var label: String
    var bundleIdentifier: String?
    var fileURL: URL?
    
    // We store the raw dictionary as a binary Data blob to ensure Sendability 
    // and avoid MainActor isolation issues common with [String: Any].
    var rawDataBlob: Data
    
    enum CodingKeys: String, CodingKey {
        case id, label, bundleIdentifier, fileURL, rawDataBlob
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        rawDataBlob = try container.decode(Data.self, forKey: .rawDataBlob)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(rawDataBlob, forKey: .rawDataBlob)
    }
    
    init(label: String, bundleIdentifier: String?, fileURL: URL?, rawDataBlob: Data) {
        self.label = label
        self.bundleIdentifier = bundleIdentifier
        self.fileURL = fileURL
        self.rawDataBlob = rawDataBlob
    }
    
    static func == (lhs: DockTile, rhs: DockTile) -> Bool {
        lhs.label == rhs.label && 
        lhs.bundleIdentifier == rhs.bundleIdentifier && 
        lhs.fileURL == rhs.fileURL
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(bundleIdentifier)
        hasher.combine(fileURL)
    }
}

// MARK: - Dock Set
struct DockSet: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var dateCreated: Date
    var tiles: [DockTile]
    
    static func == (lhs: DockSet, rhs: DockSet) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.tiles == rhs.tiles
    }
}

// MARK: - Config
struct DockConfig: Codable, Equatable, Sendable {
    var dockSets: [DockSet] = []
    var defaultDockSetID: UUID?
    var spaceAssignments: [String: UUID] = [:]
    var isAutomationEnabled: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case dockSets, defaultDockSetID, spaceAssignments, isAutomationEnabled
    }
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dockSets = try container.decodeIfPresent([DockSet].self, forKey: .dockSets) ?? []
        defaultDockSetID = try container.decodeIfPresent(UUID.self, forKey: .defaultDockSetID)
        spaceAssignments = try container.decodeIfPresent([String: UUID].self, forKey: .spaceAssignments) ?? [:]
        isAutomationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAutomationEnabled) ?? true
    }
}
    
    enum CodingKeys: String, CodingKey {
        case dockSets, defaultDockSetID, spaceAssignments, isAutomationEnabled
    }
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dockSets = try container.decodeIfPresent([DockSet].self, forKey: .dockSets) ?? []
        defaultDockSetID = try container.decodeIfPresent(UUID.self, forKey: .defaultDockSetID)
        spaceAssignments = try container.decodeIfPresent([String: UUID].self, forKey: .spaceAssignments) ?? [:]
        isAutomationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAutomationEnabled) ?? true
    }
}

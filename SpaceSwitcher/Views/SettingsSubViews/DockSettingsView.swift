import SwiftUI
import UniformTypeIdentifiers

struct DockSettingsView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var selectedSetID: UUID?
    @State private var showingNameSheet = false
    @State private var newSetName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Dock Sets").font(.headline)
                Spacer()
                Button {
                    newSetName = "Dock Set \(dockManager.config.dockSets.count + 1)"
                    showingNameSheet = true
                } label: {
                    Label("Capture Current Dock", systemImage: "plus.square.dashed")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 3-Pane Layout using HSplitView
            HSplitView {
                // PANE 1: LIST OF SETS
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved Docks").font(.caption).fontWeight(.bold).foregroundColor(.secondary).padding(8)
                    List(selection: $selectedSetID) {
                        ForEach(dockManager.config.dockSets) { set in
                            HStack {
                                Image(systemName: "dock.rectangle")
                                VStack(alignment: .leading) {
                                    Text(set.name).fontWeight(.medium)
                                    if dockManager.config.defaultDockSetID == set.id {
                                        Text("Default").font(.caption2).foregroundColor(.secondary)
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.1)).cornerRadius(4)
                                    }
                                }
                                Spacer()
                            }
                            .tag(set.id)
                            .contextMenu {
                                Button("Set as Default") { dockManager.config.defaultDockSetID = set.id }
                                Divider()
                                Button("Delete") { deleteSet(set) }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 180, maxWidth: 250)
                
                // PANE 2: EDITOR (Items in selected set)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Dock Contents").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                        Spacer()
                        if selectedSetID != nil {
                            Button(action: addAppToSelectedSet) {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                            .help("Add Application")
                        }
                    }
                    .padding(8)
                    
                    if let selectedID = selectedSetID,
                       let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedID }) {
                        
                        List {
                            ForEach(dockManager.config.dockSets[index].tiles) { tile in
                                HStack {
                                    // Try to resolve icon
                                    if let bid = tile.bundleIdentifier,
                                       let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)?.path {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                            .resizable().frame(width: 24, height: 24)
                                    } else {
                                        Image(systemName: "app.fill")
                                            .resizable().frame(width: 24, height: 24)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(tile.label)
                                    Spacer()
                                }
                            }
                            .onMove { indices, newOffset in
                                dockManager.config.dockSets[index].tiles.move(fromOffsets: indices, toOffset: newOffset)
                            }
                            .onDelete { indices in
                                dockManager.config.dockSets[index].tiles.remove(atOffsets: indices)
                            }
                        }
                        .listStyle(.inset)
                        
                    } else {
                        Text("Select a Dock Set to edit")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 220)
                
                // PANE 3: ASSIGNMENTS
                VStack(alignment: .leading, spacing: 0) {
                    Text("Space Assignments").font(.caption).fontWeight(.bold).foregroundColor(.secondary).padding(8)
                    
                    if dockManager.config.dockSets.isEmpty {
                        Text("No Dock Sets").foregroundColor(.secondary).padding()
                        Spacer()
                    } else {
                        List {
                            ForEach(spaceManager.availableSpaces) { space in
                                HStack {
                                    Text("\(space.number). \(space.name)")
                                    Spacer()
                                    Picker("", selection: Binding(
                                        get: { dockManager.config.spaceAssignments[space.id] ?? dockManager.config.defaultDockSetID ?? UUID() },
                                        set: { newVal in dockManager.config.spaceAssignments[space.id] = newVal }
                                    )) {
                                        if let defId = dockManager.config.defaultDockSetID,
                                           let defSet = dockManager.config.dockSets.first(where: { $0.id == defId }) {
                                            Text("Default (\(defSet.name))").tag(defId)
                                        } else {
                                            Text("Default").tag(dockManager.config.defaultDockSetID ?? UUID())
                                        }
                                        Divider()
                                        ForEach(dockManager.config.dockSets) { set in
                                            if set.id != dockManager.config.defaultDockSetID {
                                                Text(set.name).tag(set.id)
                                            }
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 120)
                                }
                            }
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(minWidth: 250)
            }
        }
        // Moved Sheet to root of view to prevent layout lockups
        .sheet(isPresented: $showingNameSheet) {
            VStack(spacing: 20) {
                Text("Capture Current Dock").font(.headline)
                TextField("Name", text: $newSetName)
                    .frame(width: 250)
                    .onSubmit { saveNewSet() }
                
                HStack {
                    Button("Cancel") { showingNameSheet = false }
                    Button("Capture") { saveNewSet() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Actions
    private func saveNewSet() {
        dockManager.captureCurrentDock(as: newSetName)
        showingNameSheet = false
    }
    
    private func deleteSet(_ set: DockSet) {
        dockManager.config.dockSets.removeAll { $0.id == set.id }
        if selectedSetID == set.id { selectedSetID = nil }
        // Default fallback logic
        if dockManager.config.defaultDockSetID == set.id {
            dockManager.config.defaultDockSetID = dockManager.config.dockSets.first?.id
        }
    }
    
    private func addAppToSelectedSet() {
        guard let selectedID = selectedSetID,
              let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedID }) else { return }
        
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let newTile = dockManager.createTile(from: url)
                    DispatchQueue.main.async {
                        dockManager.config.dockSets[index].tiles.append(newTile)
                    }
                }
            }
        }
    }
}

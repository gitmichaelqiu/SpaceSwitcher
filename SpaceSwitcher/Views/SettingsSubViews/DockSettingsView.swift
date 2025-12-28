import SwiftUI
import UniformTypeIdentifiers

struct DockSettingsView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var selectedSetID: UUID?
    @State private var showingCreateSheet = false
    @State private var newSetName = ""
    
    var body: some View {
        HSplitView {
            // MARK: - SIDEBAR
            VStack(spacing: 0) {
                List(selection: $selectedSetID) {
                    Section(header: Text("Dock Sets")) {
                        ForEach(dockManager.config.dockSets) { set in
                            HStack {
                                Image(systemName: "dock.rectangle")
                                Text(set.name).fontWeight(.medium)
                                Spacer()
                                if dockManager.config.defaultDockSetID == set.id {
                                    Image(systemName: "star.fill").foregroundColor(.yellow).font(.caption)
                                }
                            }
                            .tag(set.id)
                            .contextMenu { Button("Delete") { deleteSet(set) } }
                        }
                    }
                }
                .listStyle(.sidebar)
                
                Divider()
                
                Button {
                    newSetName = "Dock Set \(dockManager.config.dockSets.count + 1)"
                    showingCreateSheet = true
                } label: {
                    HStack { Image(systemName: "plus.circle.fill"); Text("New Dock Set") }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                }
                .buttonStyle(.borderless)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(minWidth: 200, maxWidth: 250)
            
            // MARK: - DETAIL
            Group {
                if let selectedID = selectedSetID,
                   let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedID }) {
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack {
                            TextField("Dock Name", text: $dockManager.config.dockSets[index].name)
                                .font(.title2).textFieldStyle(.plain)
                            Spacer()
                            Toggle(isOn: Binding(
                                get: { dockManager.config.defaultDockSetID == selectedID },
                                set: { if $0 { dockManager.config.defaultDockSetID = selectedID } }
                            )) { Text("Set as Default") }.toggleStyle(.switch)
                        }
                        .padding(20).background(Color(NSColor.controlBackgroundColor))
                        Divider()
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                
                                // SPACES SECTION (Hidden for Default)
                                if dockManager.config.defaultDockSetID != selectedID {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Apply to Spaces").font(.headline)
                                        
                                        if spaceManager.availableSpaces.isEmpty {
                                            Text("No spaces detected.").foregroundColor(.secondary).italic()
                                        } else {
                                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                                                ForEach(spaceManager.availableSpaces) { space in
                                                    // Determine State
                                                    let assignedSetID = dockManager.config.spaceAssignments[space.id]
                                                    let isAssignedHere = (assignedSetID == selectedID)
                                                    let isAssignedElsewhere = (assignedSetID != nil && !isAssignedHere)
                                                    
                                                    Toggle(isOn: Binding(
                                                        get: { isAssignedHere },
                                                        set: { val in
                                                            if val {
                                                                dockManager.config.spaceAssignments[space.id] = selectedID
                                                            } else {
                                                                dockManager.config.spaceAssignments.removeValue(forKey: space.id)
                                                            }
                                                        }
                                                    )) {
                                                        VStack(alignment: .leading) {
                                                            Text("\(space.number). \(space.name)")
                                                                .font(.subheadline).lineLimit(1)
                                                            if isAssignedElsewhere {
                                                                Text("Used in other set")
                                                                    .font(.caption2).foregroundColor(.secondary)
                                                            }
                                                        }
                                                    }
                                                    .toggleStyle(.button)
                                                    .buttonStyle(.bordered)
                                                    .tint(isAssignedHere ? .blue : .gray)
                                                    .disabled(isAssignedElsewhere) // Force strict 1:1 assignment
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    Divider().padding(.horizontal, 20)
                                } else {
                                    HStack {
                                        Image(systemName: "info.circle.fill").foregroundColor(.secondary)
                                        Text("This is the default dock. It applies to all spaces not assigned to other sets.")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 20)
                                    Divider().padding(.horizontal, 20)
                                }
                                
                                // CONTENT SECTION
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Dock Items").font(.headline)
                                        Spacer()
                                        Button(action: addAppToSelectedSet) { Label("Add App", systemImage: "plus") }.controlSize(.small)
                                    }
                                    
                                    List {
                                        ForEach(dockManager.config.dockSets[index].tiles) { tile in
                                            HStack(spacing: 12) {
                                                if let bid = tile.bundleIdentifier,
                                                   let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)?.path {
                                                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 32, height: 32)
                                                } else {
                                                    Image(systemName: "questionmark.app.dashed").resizable().frame(width: 32, height: 32).foregroundColor(.secondary)
                                                }
                                                Text(tile.label).font(.body)
                                                Spacer()
                                            }
                                            .padding(.vertical, 4)
                                        }
                                        .onMove { indices, newOffset in
                                            dockManager.config.dockSets[index].tiles.move(fromOffsets: indices, toOffset: newOffset)
                                        }
                                        .onDelete { indices in
                                            dockManager.config.dockSets[index].tiles.remove(atOffsets: indices)
                                        }
                                    }
                                    .frame(height: 350)
                                    .listStyle(.inset)
                                    .border(Color.gray.opacity(0.2), width: 1).cornerRadius(6)
                                }
                                .padding(.horizontal, 20)
                                
                                Spacer(minLength: 40)
                            }
                            .padding(.top, 20)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "dock.rectangle").font(.system(size: 48)).foregroundColor(.secondary.opacity(0.3))
                        Text("Select a Dock Set").font(.title3).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 450)
        }
        .sheet(isPresented: $showingCreateSheet) {
            VStack(spacing: 20) {
                Text("New Dock Set").font(.headline)
                TextField("Name", text: $newSetName).frame(width: 250).onSubmit { saveNewSet() }
                HStack {
                    Button("Cancel") { showingCreateSheet = false }
                    Button("Create") { saveNewSet() }.buttonStyle(.borderedProminent)
                }
            }.padding(24)
        }
        .onAppear { if selectedSetID == nil { selectedSetID = dockManager.config.dockSets.first?.id } }
    }
    
    // ... Actions (saveNewSet, deleteSet, addAppToSelectedSet) same as before ...
    private func saveNewSet() {
        dockManager.createNewDockSet(name: newSetName)
        showingCreateSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { selectedSetID = dockManager.config.dockSets.last?.id }
    }
    private func deleteSet(_ set: DockSet) {
        dockManager.config.dockSets.removeAll { $0.id == set.id }
        // Clean assignments
        let keys = dockManager.config.spaceAssignments.filter { $0.value == set.id }.map { $0.key }
        keys.forEach { dockManager.config.spaceAssignments.removeValue(forKey: $0) }
        
        if selectedSetID == set.id { selectedSetID = dockManager.config.dockSets.first?.id }
        if dockManager.config.defaultDockSetID == set.id { dockManager.config.defaultDockSetID = dockManager.config.dockSets.first?.id }
    }
    private func addAppToSelectedSet() {
        guard let targetID = selectedSetID else { return } // Capture ID, not index

        let panel = NSOpenPanel()
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let newTile = dockManager.createTile(from: url)
                    DispatchQueue.main.async {
                        if let freshIndex = self.dockManager.config.dockSets.firstIndex(where: { $0.id == targetID }) {
                            self.dockManager.config.dockSets[freshIndex].tiles.append(newTile)
                        }
                    }
                }
            }
        }
    }
}

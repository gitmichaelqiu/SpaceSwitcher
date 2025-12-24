import SwiftUI
import UniformTypeIdentifiers

struct DockSettingsView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    
    // Selection state
    @State private var selectedSetID: UUID?
    
    // Creation state
    @State private var showingCreateSheet = false
    @State private var newSetName = ""
    
    var body: some View {
        HSplitView {
            // MARK: - LEFT SIDEBAR (List of Sets)
            VStack(spacing: 0) {
                // List
                List(selection: $selectedSetID) {
                    Section(header: Text("Dock Sets")) {
                        ForEach(dockManager.config.dockSets) { set in
                            HStack {
                                Image(systemName: "dock.rectangle")
                                Text(set.name)
                                    .fontWeight(.medium)
                                Spacer()
                                if dockManager.config.defaultDockSetID == set.id {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                }
                            }
                            .tag(set.id)
                            .padding(.vertical, 4)
                            .contextMenu {
                                Button("Delete") { deleteSet(set) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                
                Divider()
                
                // Bottom Button
                Button {
                    newSetName = "Dock Set \(dockManager.config.dockSets.count + 1)"
                    showingCreateSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create New Dock Set")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                }
                .buttonStyle(.borderless)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(minWidth: 200, maxWidth: 250)
            
            // MARK: - RIGHT DETAIL (Editor)
            Group {
                if let selectedID = selectedSetID,
                   let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedID }) {
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // 1. Header (Title & Default)
                        HStack(alignment: .center) {
                            TextField("Dock Name", text: $dockManager.config.dockSets[index].name)
                                .font(.title2)
                                .textFieldStyle(.plain)
                            
                            Spacer()
                            
                            Toggle(isOn: Binding(
                                get: { dockManager.config.defaultDockSetID == selectedID },
                                set: { if $0 { dockManager.config.defaultDockSetID = selectedID } }
                            )) {
                                Text("Default Dock")
                            }
                            .toggleStyle(.switch)
                            .help("This dock will be used for any space not explicitly assigned.")
                        }
                        .padding(20)
                        .background(Color(NSColor.controlBackgroundColor))
                        
                        Divider()
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                
                                // 2. Spaces Assignment
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Apply to Spaces")
                                        .font(.headline)
                                    
                                    if spaceManager.availableSpaces.isEmpty {
                                        Text("No spaces detected.")
                                            .foregroundColor(.secondary)
                                            .italic()
                                    } else {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                                            ForEach(spaceManager.availableSpaces) { space in
                                                // Check if this space is assigned to THIS set
                                                let isAssigned = (dockManager.config.spaceAssignments[space.id] == selectedID)
                                                
                                                Toggle(isOn: Binding(
                                                    get: { isAssigned },
                                                    set: { isActive in
                                                        if isActive {
                                                            // Assign to this set (steals from others)
                                                            dockManager.config.spaceAssignments[space.id] = selectedID
                                                        } else {
                                                            // Remove assignment
                                                            dockManager.config.spaceAssignments.removeValue(forKey: space.id)
                                                        }
                                                    }
                                                )) {
                                                    Text("\(space.number). \(space.name)")
                                                        .font(.subheadline)
                                                        .lineLimit(1)
                                                }
                                                .toggleStyle(.button)
                                                .buttonStyle(.bordered)
                                                .tint(isAssigned ? .blue : .gray)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                
                                Divider().padding(.horizontal, 20)
                                
                                // 3. Dock Contents
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Dock Items")
                                            .font(.headline)
                                        Spacer()
                                        Button(action: addAppToSelectedSet) {
                                            Label("Add App", systemImage: "plus")
                                        }
                                        .controlSize(.small)
                                    }
                                    
                                    List {
                                        ForEach(dockManager.config.dockSets[index].tiles) { tile in
                                            HStack(spacing: 12) {
                                                if let bid = tile.bundleIdentifier,
                                                   let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)?.path {
                                                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                                        .resizable().frame(width: 32, height: 32)
                                                } else {
                                                    Image(systemName: "questionmark.app.dashed")
                                                        .resizable().frame(width: 32, height: 32)
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                Text(tile.label)
                                                    .font(.body)
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
                                    .frame(height: 300) // Fixed height for list within scroll
                                    .listStyle(.inset)
                                    .border(Color.gray.opacity(0.2), width: 1)
                                    .cornerRadius(6)
                                }
                                .padding(.horizontal, 20)
                                
                                Spacer(minLength: 20)
                            }
                            .padding(.top, 20)
                        }
                    }
                } else {
                    // Empty State
                    VStack(spacing: 16) {
                        Image(systemName: "dock.rectangle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Select a Dock Set")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Or create a new one from the sidebar.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        // Attached Sheet
        .sheet(isPresented: $showingCreateSheet) {
            VStack(spacing: 20) {
                Text("New Dock Set").font(.headline)
                Text("This will capture your current Dock layout as a starting point.")
                    .font(.caption).foregroundColor(.secondary)
                
                TextField("Name", text: $newSetName)
                    .frame(width: 250)
                    .onSubmit { saveNewSet() }
                
                HStack {
                    Button("Cancel") { showingCreateSheet = false }
                    Button("Create") { saveNewSet() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        // Auto-select first item if nothing selected
        .onAppear {
            if selectedSetID == nil {
                selectedSetID = dockManager.config.dockSets.first?.id
            }
        }
    }
    
    // MARK: - Logic
    private func saveNewSet() {
        dockManager.createNewDockSet(name: newSetName)
        showingCreateSheet = false
        // Auto select new set (last one)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            selectedSetID = dockManager.config.dockSets.last?.id
        }
    }
    
    private func deleteSet(_ set: DockSet) {
        // Remove from list
        dockManager.config.dockSets.removeAll { $0.id == set.id }
        
        // Remove from assignments
        let keysToRemove = dockManager.config.spaceAssignments.filter { $0.value == set.id }.map { $0.key }
        for key in keysToRemove {
            dockManager.config.spaceAssignments.removeValue(forKey: key)
        }
        
        // Reset selection if deleted
        if selectedSetID == set.id {
            selectedSetID = dockManager.config.dockSets.first?.id
        }
        
        // Reset default if deleted
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

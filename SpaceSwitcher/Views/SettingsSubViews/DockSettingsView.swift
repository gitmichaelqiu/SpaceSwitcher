import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Container
struct DockSettingsView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var selectedSetID: UUID?
    @State private var showingCreateSheet = false
    @State private var newSetName = ""
    
    var body: some View {
        HSplitView {
            // LEFT: Sidebar
            DockSidebarView(
                dockManager: dockManager,
                selectedSetID: $selectedSetID,
                showingCreateSheet: $showingCreateSheet,
                newSetName: $newSetName
            )
            .frame(minWidth: 200, maxWidth: 250)
            
            // RIGHT: Detail Area
            Group {
                if let selectedID = selectedSetID,
                   let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedID }) {
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // 1. Header (Name + Default Toggle)
                        DockHeaderView(
                            set: $dockManager.config.dockSets[index],
                            config: $dockManager.config
                        )
                        
                        Divider()
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                
                                // 2. Space Assignments
                                DockSpaceAssignmentView(
                                    selectedSetID: selectedID,
                                    dockManager: dockManager,
                                    spaceManager: spaceManager
                                )
                                
                                // 3. Dock Items List (Apps + Spacers)
                                DockItemsListView(
                                    dockManager: dockManager,
                                    selectedSetID: selectedID, // Pass ID for robust lookups
                                    tiles: $dockManager.config.dockSets[index].tiles
                                )
                                
                                Spacer(minLength: 40)
                            }
                            .padding(.top, 20)
                        }
                    }
                } else {
                    EmptySelectionView()
                }
            }
            .frame(minWidth: 450)
        }
        // Create Sheet Logic
        .sheet(isPresented: $showingCreateSheet) {
            CreateDockSheet(
                newSetName: $newSetName,
                onCancel: { showingCreateSheet = false },
                onCreate: saveNewSet
            )
        }
        .onAppear {
            if selectedSetID == nil { selectedSetID = dockManager.config.dockSets.first?.id }
        }
    }
    
    // MARK: - Parent Actions
    private func saveNewSet() {
        dockManager.createNewDockSet(name: newSetName)
        showingCreateSheet = false
        // Select the new set (brief delay to ensure UI updates)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            selectedSetID = dockManager.config.dockSets.last?.id
        }
    }
}

// MARK: - Component 1: Sidebar
struct DockSidebarView: View {
    @ObservedObject var dockManager: DockManager
    @Binding var selectedSetID: UUID?
    @Binding var showingCreateSheet: Bool
    @Binding var newSetName: String
    
    var body: some View {
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
    }
    
    private func deleteSet(_ set: DockSet) {
        dockManager.config.dockSets.removeAll { $0.id == set.id }
        // Clean assignments
        let keys = dockManager.config.spaceAssignments.filter { $0.value == set.id }.map { $0.key }
        keys.forEach { dockManager.config.spaceAssignments.removeValue(forKey: $0) }
        
        if selectedSetID == set.id { selectedSetID = dockManager.config.dockSets.first?.id }
        if dockManager.config.defaultDockSetID == set.id {
            dockManager.config.defaultDockSetID = dockManager.config.dockSets.first?.id
        }
    }
}

// MARK: - Component 2: Header (Name + Default)
struct DockHeaderView: View {
    @Binding var set: DockSet
    @Binding var config: DockConfig
    
    var body: some View {
        HStack {
            TextField("Dock Name", text: $set.name)
                .font(.title2)
                .textFieldStyle(.plain)
            
            Spacer()
            
            Toggle(isOn: Binding(
                get: { config.defaultDockSetID == set.id },
                set: { if $0 { config.defaultDockSetID = set.id } }
            )) {
                Text("Set as Default")
            }
            .toggleStyle(.switch)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Component 3: Space Assignments
struct DockSpaceAssignmentView: View {
    let selectedSetID: UUID
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    
    var body: some View {
        if dockManager.config.defaultDockSetID != selectedSetID {
            VStack(alignment: .leading, spacing: 12) {
                Text("Apply to Spaces").font(.headline)
                
                if spaceManager.availableSpaces.isEmpty {
                    Text("No spaces detected.").foregroundColor(.secondary).italic()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                        ForEach(spaceManager.availableSpaces) { space in
                            // Logic for assignment state
                            let assignedSetID = dockManager.config.spaceAssignments[space.id]
                            let isAssignedHere = (assignedSetID == selectedSetID)
                            let isAssignedElsewhere = (assignedSetID != nil && !isAssignedHere)
                            
                            Toggle(isOn: Binding(
                                get: { isAssignedHere },
                                set: { val in
                                    if val {
                                        dockManager.config.spaceAssignments[space.id] = selectedSetID
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
            // Info banner for default dock
            HStack {
                Image(systemName: "info.circle.fill").foregroundColor(.secondary)
                Text("This is the default dock. It applies to all spaces not assigned to other sets.")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            Divider().padding(.horizontal, 20)
        }
    }
}

// MARK: - Component 4: Dock Items List (Apps + Spacers)
struct DockItemsListView: View {
    @ObservedObject var dockManager: DockManager
    let selectedSetID: UUID
    @Binding var tiles: [DockTile]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dock Items").font(.headline)
                Spacer()
                
                // ADD ITEM MENU
                Menu {
                    Button {
                        addAppToSelectedSet()
                    } label: {
                        Label("Application...", systemImage: "plus.app")
                    }
                    
                    Divider()
                    
                    Button {
                        addSpacerToSelectedSet(isSmall: false)
                    } label: {
                        Label("Large Spacer", systemImage: "arrow.left.and.right.square")
                    }
                    
                    Button {
                        addSpacerToSelectedSet(isSmall: true)
                    } label: {
                        Label("Small Spacer", systemImage: "arrow.left.and.right.square.fill")
                    }
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()
            }
            
            List {
                ForEach(tiles) { tile in
                    DockTileRow(tile: tile)
                }
                .onMove { indices, newOffset in
                    tiles.move(fromOffsets: indices, toOffset: newOffset)
                }
                .onDelete { indices in
                    tiles.remove(atOffsets: indices)
                }
            }
            .frame(height: 350)
            .listStyle(.inset)
            .border(Color.gray.opacity(0.2), width: 1).cornerRadius(6)
        }
        .padding(.horizontal, 20)
    }
    
    // Actions
    private func addAppToSelectedSet() {
        let panel = NSOpenPanel()
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let newTile = dockManager.createTile(from: url)
                    DispatchQueue.main.async {
                        // We must find the set again in the manager to append safely
                        if let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedSetID }) {
                            dockManager.config.dockSets[index].tiles.append(newTile)
                        }
                    }
                }
            }
        }
    }
    
    private func addSpacerToSelectedSet(isSmall: Bool) {
        let spacer = dockManager.createSpacerTile(isSmall: isSmall)
        DispatchQueue.main.async {
            if let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedSetID }) {
                dockManager.config.dockSets[index].tiles.append(spacer)
            }
        }
    }
}

// MARK: - Sub-Component: Dock Tile Row
struct DockTileRow: View {
    let tile: DockTile
    
    var body: some View {
        HStack(spacing: 12) {
            iconView
            Text(tile.label).font(.body)
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var iconView: some View {
        if let bid = tile.bundleIdentifier,
           let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)?.path {
            // Regular App Icon
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 32, height: 32)
        } else if tile.label == "Large Spacer" {
            // Large Spacer Icon
            Image(systemName: "arrow.left.and.right.square")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .frame(width: 32, height: 32)
        } else if tile.label == "Small Spacer" {
            // Small Spacer Icon
            Image(systemName: "arrow.left.and.right.square.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .frame(width: 32, height: 32)
        } else {
            // Fallback
            Image(systemName: "questionmark.app.dashed")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Helpers: Sheets & Empty States
struct CreateDockSheet: View {
    @Binding var newSetName: String
    let onCancel: () -> Void
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Dock Set").font(.headline)
            TextField("Name", text: $newSetName)
                .frame(width: 250)
                .onSubmit(onCreate)
            
            HStack {
                Button("Cancel", action: onCancel)
                Button("Create", action: onCreate).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}

struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))
            Text("Select a Dock Set")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

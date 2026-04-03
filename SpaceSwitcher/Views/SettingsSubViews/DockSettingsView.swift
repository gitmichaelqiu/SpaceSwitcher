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
            .frame(minWidth: 200, maxWidth: 260)
            
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
                        
                        Divider().opacity(0.5)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 32) {
                                
                                // 2. Space Assignments
                                DockSpaceAssignmentView(
                                    selectedSetID: selectedID,
                                    dockManager: dockManager,
                                    spaceManager: spaceManager
                                )
                                
                                // 3. Dock Items List (Apps + Spacers)
                                DockItemsListView(
                                    dockManager: dockManager,
                                    spaceManager: spaceManager,
                                    selectedSetID: selectedID,
                                    tiles: $dockManager.config.dockSets[index].tiles
                                )
                                
                                Spacer(minLength: 40)
                            }
                            .padding(.vertical, 24)
                        }
                    }
                } else {
                    EmptySelectionView()
                }
            }
            .frame(minWidth: 460)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
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
                Section {
                    ForEach(dockManager.config.dockSets) { set in
                        HStack(spacing: 10) {
                            // Status Indicator
                            Circle()
                                .fill(dockManager.activeDockSetID == set.id ? Color.green : Color.clear)
                                .frame(width: 6, height: 6)
                            
                            Image(systemName: "dock.rectangle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            
                            Text(set.name)
                                .font(.system(size: 13, weight: .medium))
                            
                            Spacer()
                            
                            if dockManager.config.defaultDockSetID == set.id {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange.opacity(0.8))
                                    .font(.system(size: 10))
                                    .help("Default Dock Set")
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(set.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) { deleteSet(set) }
                        }
                    }
                } header: {
                    Text("Dock Sets")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
            }
            .listStyle(.sidebar)
            
            Divider().opacity(0.5)
            
            Button {
                newSetName = "Dock Set \(dockManager.config.dockSets.count + 1)"
                showingCreateSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Dock Set")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
    
    private func deleteSet(_ set: DockSet) {
        withAnimation {
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
}

// MARK: - Component 2: Header (Name + Default)
struct DockHeaderView: View {
    @Binding var set: DockSet
    @Binding var config: DockConfig
    
    var body: some View {
        HStack(alignment: .center) {
            TextField("Rename Dock Set", text: $set.name)
                .font(.system(size: 20, weight: .bold))
                .textFieldStyle(.plain)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text("Default")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Toggle("", isOn: Binding(
                    get: { config.defaultDockSetID == set.id },
                    set: { if $0 { config.defaultDockSetID = set.id } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.8)
                .disabled(config.defaultDockSetID == set.id)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }
}

// MARK: - Component 3: Space Assignments
struct DockSpaceAssignmentView: View {
    let selectedSetID: UUID
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Assignment")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                if dockManager.config.defaultDockSetID == selectedSetID {
                    Text("Applied as default fallback")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .italic()
                }
            }
            .padding(.horizontal, 4)
            
            if dockManager.config.defaultDockSetID != selectedSetID {
                VStack(alignment: .leading, spacing: 12) {
                    if spaceManager.availableSpaces.isEmpty {
                        HStack {
                            Spacer()
                            Text("No spaces detected.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .italic()
                            Spacer()
                        }
                        .padding(20)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                            ForEach(spaceManager.availableSpaces) { space in
                                let assignedSetID = dockManager.config.spaceAssignments[space.id]
                                let isAssignedHere = (assignedSetID == selectedSetID)
                                let isAssignedElsewhere = (assignedSetID != nil && !isAssignedHere)
                                
                                Button {
                                    if isAssignedHere {
                                        dockManager.config.spaceAssignments.removeValue(forKey: space.id)
                                    } else if !isAssignedElsewhere {
                                        dockManager.config.spaceAssignments[space.id] = selectedSetID
                                    }
                                } label: {
                                    VStack(alignment: .center, spacing: 4) {
                                        Text("\(space.number)")
                                            .font(.system(size: 14, weight: .bold))
                                        Text(space.name)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isAssignedHere ? Color.accentColor : Color.primary.opacity(0.05))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(isAssignedElsewhere ? Color.secondary.opacity(0.2) : Color.clear, lineWidth: 1)
                                            )
                                    )
                                    .foregroundColor(isAssignedHere ? .white : (isAssignedElsewhere ? .secondary.opacity(0.4) : .primary))
                                }
                                .buttonStyle(.plain)
                                .disabled(isAssignedElsewhere)
                                .help(isAssignedElsewhere ? "Assigned to another dock set" : "")
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange.opacity(0.8))
                    Text("This dock set will be used automatically for any space that doesn't have a specific assignment.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.05))
                )
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Component 4: Dock Items List
struct DockItemsListView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    let selectedSetID: UUID
    @Binding var tiles: [DockTile]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // MARK: - Header & Actions
            HStack(alignment: .firstTextBaseline) {
                Text("Dock Items")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        forceApply()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Apply")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Apply this dock to the current space now")
                    
                    Divider().frame(height: 12).padding(.horizontal, 4)
                    
                    Menu {
                        Button { addAppToSelectedSet() } label: { Label("Add Application...", systemImage: "app.badge.plus") }
                        Divider()
                        Button { addSpacerToSelectedSet(isSmall: false) } label: { Label("Add Large Spacer", systemImage: "spacer") }
                        Button { addSpacerToSelectedSet(isSmall: true) } label: { Label("Add Small Spacer", systemImage: "command") }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add Item")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 4)
            
            // MARK: - List View
            VStack(spacing: 0) {
                if tiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dock.rectangle")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.2))
                        Text("No items in this dock set")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    List {
                        ForEach(tiles) { tile in
                            DockTileRow(tile: tile)
                                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                                .listRowSeparator(.visible, edges: .bottom)
                        }
                        .onMove { indices, newOffset in
                            tiles.move(fromOffsets: indices, toOffset: newOffset)
                        }
                        .onDelete { indices in
                            tiles.remove(atOffsets: indices)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 300, maxHeight: 500)
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            
            Text("Drag items to reorder. Swipe or press Backspace to delete.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
    }
    
    private func forceApply() {
        guard let currentSpace = spaceManager.currentSpaceID else { return }
        dockManager.applyDockForSpace(currentSpace, force: true)
    }
    
    private func addAppToSelectedSet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let newTile = dockManager.createTile(from: url)
                    DispatchQueue.main.async {
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

struct DockTileRow: View {
    let tile: DockTile
    
    var body: some View {
        HStack(spacing: 14) {
            iconView
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.label)
                    .font(.system(size: 13, weight: .medium))
                if let bid = tile.bundleIdentifier {
                    Text(bid)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            
            Spacer()
            
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.3))
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var iconView: some View {
        if let bid = tile.bundleIdentifier,
           let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)?.path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
        } else if tile.label.contains("Spacer") {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
                Image(systemName: tile.label.contains("Small") ? "arrow.left.and.right.square.fill" : "arrow.left.and.right.square")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        } else {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 20))
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
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("New Dock Set")
                    .font(.system(size: 17, weight: .bold))
                Text("Give your dock set a descriptive name.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            TextField("Name", text: $newSetName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .frame(width: 280)
                .onSubmit(onCreate)
            
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .controlSize(.large)
                
                Button("Create Set", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.1))
            
            VStack(spacing: 4) {
                Text("Select a Dock Set")
                    .font(.system(size: 17, weight: .semibold))
                Text("Choose a set from the sidebar to manage its items and assignments.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

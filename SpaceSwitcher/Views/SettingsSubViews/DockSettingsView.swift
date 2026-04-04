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
            .frame(minWidth: 200, maxWidth: 300)
            .layoutPriority(0)
            
            // RIGHT: Detail Area
            ZStack {
                if let selectedID = selectedSetID,
                   let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedID }) {
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // 1. Header (Name + Default Toggle)
                        DockHeaderView(
                            set: $dockManager.config.dockSets[index],
                            config: $dockManager.config
                        )
                        
                        Divider()
                        
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 28) {
                                
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
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptySelectionView()
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
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
                        HStack(spacing: 8) {
                            // Status Indicator
                            Circle()
                                .fill(dockManager.activeDockSetID == set.id ? Color.green : Color.clear)
                                .frame(width: 6, height: 6)
                            
                            Image(systemName: "dock.rectangle")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            
                            Text(set.name)
                                .font(.system(size: 13, weight: .medium))
                            
                            Spacer()
                            
                            if dockManager.config.defaultDockSetID == set.id {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange.opacity(0.8))
                                    .font(.system(size: 9))
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(set.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) { deleteSet(set) }
                        }
                    }
                } header: {
                    Text("Dock Sets")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            Button {
                newSetName = "Dock Set \(dockManager.config.dockSets.count + 1)"
                showingCreateSheet = true
            } label: {
                HStack(spacing: 6) {
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
            TextField("Rename", text: $set.name)
                .font(.system(size: 18, weight: .bold))
                .textFieldStyle(.plain)
                .padding(.leading, 8)
            
            Spacer()
            
            Toggle("Default", isOn: Binding(
                get: { config.defaultDockSetID == set.id },
                set: { if $0 { config.defaultDockSetID = set.id } }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(config.defaultDockSetID == set.id)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }
}

// MARK: - Component 3: Space Assignments
struct DockSpaceAssignmentView: View {
    let selectedSetID: UUID
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    
    var body: some View {
        SettingsSection("Apply to Spaces") {
            if dockManager.config.defaultDockSetID != selectedSetID {
                VStack(alignment: .leading, spacing: 10) {
                    if spaceManager.availableSpaces.isEmpty {
                        Text("No spaces detected.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(12)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
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
                                    VStack(alignment: .center, spacing: 2) {
                                        Text("\(space.number)")
                                            .font(.system(size: 14, weight: .bold))
                                        Text(space.name)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isAssignedHere ? Color.accentColor : Color.primary.opacity(0.05))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(isAssignedElsewhere ? Color.secondary.opacity(0.1) : Color.clear, lineWidth: 1)
                                            )
                                    )
                                    .foregroundColor(isAssignedHere ? .white : (isAssignedElsewhere ? .secondary.opacity(0.4) : .primary))
                                }
                                .buttonStyle(.plain)
                                .disabled(isAssignedElsewhere)
                            }
                        }
                        .padding(12)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.secondary.opacity(0.5))
                        .font(.system(size: 14))
                    Text("This dock set is used automatically for all unassigned spaces.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Component 4: Dock Items List
struct DockItemsListView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    let selectedSetID: UUID
    @Binding var tiles: [DockTile]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DOCK ITEMS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        forceApply()
                    } label: {
                        Text("Apply Now")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Menu {
                        Button { addAppToSelectedSet() } label: { Label("Add Application...", systemImage: "app.badge.plus") }
                        Divider()
                        Button { addSpacerToSelectedSet(isSmall: false) } label: { Label("Add Large Spacer", systemImage: "spacer") }
                        Button { addSpacerToSelectedSet(isSmall: true) } label: { Label("Add Small Spacer", systemImage: "command") }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(.horizontal, 4)
            
            SettingsSection {
                if tiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dock.rectangle")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.1))
                        Text("No items assigned to this Dock set")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        Button { addAppToSelectedSet() } label: {
                            Text("Add First Item")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(tiles) { tile in
                            if let index = tiles.firstIndex(where: { $0.id == tile.id }) {
                                DockTileRow(
                                    tile: tile,
                                    onDelete: {
                                        tiles.remove(at: index)
                                    },
                                    moveUp: index > 0 ? {
                                        tiles.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                                    } : nil,
                                    moveDown: index < tiles.count - 1 ? {
                                        tiles.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                                    } : nil
                                )
                                
                                if index < tiles.count - 1 {
                                    Divider().opacity(0.5)
                                }
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private func forceApply() {
        guard let currentSpace = spaceManager.currentSpaceID else { return }
        dockManager.applyDockForSpace(currentSpace, force: true)
    }
    
    private func addAppToSelectedSet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
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
    let onDelete: () -> Void
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                iconView
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(tile.label)
                        .font(.system(size: 13, weight: .medium))
                    if let bid = tile.bundleIdentifier {
                        Text(bid)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Spacer()
            
            if isHovering {
                HStack(spacing: 4) {
                    if let moveUp = moveUp {
                        Button(action: moveUp) {
                            Image(systemName: "chevron.up")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                    
                    if let moveDown = moveDown {
                        Button(action: moveDown) {
                            Image(systemName: "chevron.down")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                    
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.7))
                }
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
    
    @ViewBuilder
    private var iconView: some View {
        if let bid = tile.bundleIdentifier,
           let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)?.path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if tile.label.contains("Spacer") {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                Image(systemName: "spacer")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        } else {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 16))
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
            Text("New Dock Set")
                .font(.system(size: 18, weight: .bold))
            
            TextField("Name", text: $newSetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(onCreate)
            
            HStack(spacing: 16) {
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
            Image(systemName: "dock.rectangle.on.rectangle")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.1))
            Text("Select a Dock Set to edit its configuration")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Container
struct DockSettingsView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var selectedSetID: UUID?
    @State private var showingCreateSheet = false
    @State private var newSetName = ""
    
    init(dockManager: DockManager, spaceManager: SpaceManager) {
        self.dockManager = dockManager
        self.spaceManager = spaceManager
        // Pre-select the first dock set immediately to avoid flicker
        _selectedSetID = State(initialValue: dockManager.config.dockSets.first?.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            DockSetTabBar(
                dockManager: dockManager,
                selectedSetID: $selectedSetID,
                onCreate: prepareNewSet,
                onDelete: deleteSet
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            Divider()

            ZStack {
                if let selectedID = selectedSetID,
                   let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedID }) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 24) {
                            SettingsSection("Automation") {
                                SettingsRow(
                                    "Automatically switch dock",
                                    requirements: [.spaceAPI(isAvailable: spaceManager.apiAvailability == .available)]
                                ) {
                                    Toggle("", isOn: $dockManager.config.isAutomationEnabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                }
                            }

                            SettingsSection(NSLocalizedString("Set Configuration", comment: "")) {
                                SettingsRow("Name") {
                                    TextField("Name", text: $dockManager.config.dockSets[index].name)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 150)
                                }

                                Divider()

                                SettingsRow(
                                    "Default Set",
                                    helperText: "The default set is used for any space that doesn't have a specific assignment."
                                ) {
                                    Toggle("", isOn: Binding(
                                        get: { dockManager.config.defaultDockSetID == selectedID },
                                        set: { if $0 { dockManager.config.defaultDockSetID = selectedID } }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .disabled(dockManager.config.defaultDockSetID == selectedID)
                                }
                            }

                            DockSpaceAssignmentView(
                                selectedSetID: selectedID,
                                dockManager: dockManager,
                                spaceManager: spaceManager
                            )

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
                    .frame(maxWidth: .infinity)
                } else {
                    EmptySelectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.1))
        }
        .animation(.easeInOut(duration: 0.18), value: selectedSetID)
        .sheet(isPresented: $showingCreateSheet) {
            CreateDockSheet(
                newSetName: $newSetName,
                onCancel: { showingCreateSheet = false },
                onCreate: saveNewSet
            )
        }
    }

    private func prepareNewSet() {
        newSetName = "Dock Set \(dockManager.config.dockSets.count + 1)"
        showingCreateSheet = true
    }
    
    private func deleteSet(_ set: DockSet) {
        withAnimation {
            dockManager.config.dockSets.removeAll { $0.id == set.id }
            let keys = dockManager.config.spaceAssignments.filter { $0.value == set.id }.map { $0.key }
            keys.forEach { dockManager.config.spaceAssignments.removeValue(forKey: $0) }
            
            // Selection fix
            if selectedSetID == set.id { selectedSetID = dockManager.config.dockSets.first?.id }
            
            // Default set fix: Always ensure one exists if sets are available
            if dockManager.config.defaultDockSetID == set.id || dockManager.config.defaultDockSetID == nil {
                dockManager.config.defaultDockSetID = dockManager.config.dockSets.first?.id
            }
        }
    }
    
    private func saveNewSet() {
        dockManager.createNewDockSet(name: newSetName)
        showingCreateSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            selectedSetID = dockManager.config.dockSets.last?.id
        }
    }

}

// MARK: - Dock Set Tabs
private struct DockSetTabBar: View {
    @ObservedObject var dockManager: DockManager
    @Binding var selectedSetID: UUID?
    let onCreate: () -> Void
    let onDelete: (DockSet) -> Void

    @State private var availableWidth: CGFloat = 0
    @State private var pickerWidth: CGFloat = 0

    private var selectedSet: DockSet? {
        guard let selectedSetID else { return nil }
        return dockManager.config.dockSets.first { $0.id == selectedSetID }
    }

    private var shouldScroll: Bool {
        guard availableWidth > 0, pickerWidth > 0 else { return false }
        return pickerWidth > max(availableWidth - 20, 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if shouldScroll {
                    ScrollView(.horizontal) {
                        measuredPicker
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Spacer(minLength: 0)
                        measuredPicker
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DockSetTabAvailableWidthKey.self,
                        value: proxy.size.width
                    )
                }
            }
            .onPreferenceChange(DockSetTabAvailableWidthKey.self) { width in
                guard abs(availableWidth - width) > 0.5 else { return }
                availableWidth = width
            }
            .onPreferenceChange(DockSetTabPickerWidthKey.self) { width in
                guard abs(pickerWidth - width) > 0.5 else { return }
                pickerWidth = width
            }

            Button(action: onCreate) {
                Image(systemName: "plus")
            }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(width: 32, height: 32)
                .help("New Dock Set")
                .accessibilityLabel("New Dock Set")

            if let selectedSet, dockManager.config.dockSets.count > 1 {
                Button(role: .destructive) {
                    onDelete(selectedSet)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(width: 32, height: 32)
                .help("Delete Dock Set")
                .accessibilityLabel("Delete Dock Set")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var measuredPicker: some View {
        picker
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DockSetTabPickerWidthKey.self,
                        value: proxy.size.width
                    )
                }
            }
    }

    @ViewBuilder
    private var picker: some View {
        if #available(macOS 27.0, *) {
            Picker("Dock Set", selection: $selectedSetID) {
                pickerOptions
            }
            .labelsHidden()
            .pickerStyle(.tabs)
            .controlSize(.large)
        } else {
            Picker("Dock Set", selection: $selectedSetID) {
                pickerOptions
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var pickerOptions: some View {
        ForEach(dockManager.config.dockSets) { set in
            Text(set.id == dockManager.activeDockSetID ? "○ \(set.name)" : set.name)
                .lineLimit(1)
                .accessibilityLabel(
                    set.id == dockManager.activeDockSetID
                        ? "\(set.name), active"
                        : set.name
                )
                .tag(Optional(set.id))
        }
    }
}

private struct DockSetTabPickerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DockSetTabAvailableWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Component 2: Space Assignments
struct DockSpaceAssignmentView: View {
    let selectedSetID: UUID
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager

    private var assignmentHelperText: LocalizedStringKey? {
        guard dockManager.config.isAutomationEnabled else {
            return "Space assignments are saved but only applied when Automatically switch dock is enabled."
        }

        guard dockManager.config.defaultDockSetID == selectedSetID else { return nil }
        return "This dock set is used automatically for all unassigned spaces."
    }
    
    var body: some View {
        let isDefault = dockManager.config.defaultDockSetID == selectedSetID
        
        SettingsSection(
            NSLocalizedString("Apply to Spaces", comment: ""),
            helperText: assignmentHelperText
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if spaceManager.availableSpaces.isEmpty {
                    Text("No spaces detected.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 140))], spacing: 12) {
                        ForEach(spaceManager.availableSpaces) { space in
                            spaceCard(for: space, isDefault: isDefault)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func spaceCard(for space: SpaceInfo, isDefault: Bool) -> some View {
        let assignedSetID = dockManager.config.spaceAssignments[space.id]
        let isAssignedHere = (assignedSetID == selectedSetID)
        let isAssignedElsewhere = (assignedSetID != nil && !isAssignedHere)

        return DockSpaceCard(
            space: space,
            isHighlighted: isDefault ? !isAssignedElsewhere : isAssignedHere,
            isDimmed: isAssignedElsewhere,
            isInteractive: !isDefault,
            onTap: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if isAssignedHere {
                        dockManager.config.spaceAssignments.removeValue(forKey: space.id)
                    } else if !isAssignedElsewhere {
                        dockManager.config.spaceAssignments[space.id] = selectedSetID
                    }
                }
            }
        )
    }
}

private struct DockSpaceCard: View {
    let space: SpaceInfo
    let isHighlighted: Bool
    let isDimmed: Bool
    let isInteractive: Bool
    let onTap: () -> Void

    var body: some View {
        if isInteractive {
            Button(action: onTap) {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .center, spacing: 2) {
            Text("\(space.number)")
                .font(.body.weight(.semibold))
            Text(space.name)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isDimmed ? Color.secondary.opacity(0.12) : Color.clear, lineWidth: 1)
                )
        )
        .foregroundStyle(isHighlighted ? Color.white : (isDimmed ? Color.secondary.opacity(0.45) : Color.primary))
    }
}

// MARK: - Component 3: Dock Items List
struct DockItemsListView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    let selectedSetID: UUID
    @Binding var tiles: [DockTile]

    @State private var showingCurrentDockReadError = false
    
    var body: some View {
        SettingsSection(
            NSLocalizedString("Dock Items", comment: ""),
            accessory: {
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
                        Button {
                            replaceWithCurrentDock()
                        } label: {
                            Label("Replace with Current Dock Items", systemImage: "arrow.down.doc")
                        }

                        Divider()

                        Button { addAppToSelectedSet() } label: { Label("Add Application...", systemImage: "plus.app") }
                        Divider()
                        Button { addSpacerToSelectedSet(isSmall: false) } label: { Label("Add Large Spacer", systemImage: "square") }
                        Button { addSpacerToSelectedSet(isSmall: true) } label: { Label("Add Small Spacer", systemImage: "square.dashed") }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        ) {
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
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        _tiles.wrappedValue = _tiles.wrappedValue.enumerated()
                                            .filter { $0.offset != index }
                                            .map { $0.element }
                                    }
                                },
                                moveUp: index > 0 ? {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        _tiles.wrappedValue.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                                    }
                                } : nil,
                                moveDown: index < tiles.count - 1 ? {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        _tiles.wrappedValue.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                                    }
                                } : nil
                            )
                            
                            if index < tiles.count - 1 {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: tiles)
            }
        }
        .alert("Could Not Read Current Dock", isPresented: $showingCurrentDockReadError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("SpaceSwitcher could not read the current Dock items.")
        }
    }

    private func replaceWithCurrentDock() {
        guard dockManager.replaceDockItemsWithCurrentDock(for: selectedSetID) else {
            showingCurrentDockReadError = true
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            tiles = dockManager.config.dockSets.first(where: { $0.id == selectedSetID })?.tiles ?? []
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedSetID }) {
                                dockManager.config.dockSets[index].tiles.append(newTile)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func addSpacerToSelectedSet(isSmall: Bool) {
        let spacer = dockManager.createSpacerTile(isSmall: isSmall)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                if let index = dockManager.config.dockSets.firstIndex(where: { $0.id == selectedSetID }) {
                    dockManager.config.dockSets[index].tiles.append(spacer)
                }
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
                        .font(.body.weight(.medium))
                    if let bid = tile.bundleIdentifier {
                        BundleIdentifierText(bid)
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
        .frame(minHeight: 44, alignment: .center)
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

import SwiftUI
import AppKit
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
                    SettingsContainer(.dock) {
                        VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionSpacing) {
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

                            SettingsSection("Set Configuration") {
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
                                    Picker("", selection: Binding(
                                        get: { dockManager.config.defaultDockSetID ?? selectedID },
                                        set: { dockManager.config.defaultDockSetID = $0 }
                                    )) {
                                        ForEach(dockManager.config.dockSets) { dockSet in
                                            Text(dockSet.name).tag(dockSet.id)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    EmptySelectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var selectedSet: DockSet? {
        guard let selectedSetID else { return nil }
        return dockManager.config.dockSets.first { $0.id == selectedSetID }
    }

    var body: some View {
        HStack(spacing: 8) {
            NativeHorizontalScrollView {
                nativePicker
                    .fixedSize(horizontal: true, vertical: false)
            }
            // NSScrollView has no useful intrinsic height of its own. Keep
            // the bridge at the same 36-point height as the native tab
            // control so horizontal overflow never expands the settings
            // layout vertically.
            .frame(height: SettingsComponentMetrics.listRowHeight)
            .frame(maxWidth: .infinity)

            Button(action: onCreate) {
                SettingsIconControlLabel(systemName: "plus")
            }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .settingsIconControlFrame()
                .help("New Dock Set")
                .accessibilityLabel("New Dock Set")

            if let selectedSet, dockManager.config.dockSets.count > 1 {
                Button(role: .destructive) {
                    onDelete(selectedSet)
                } label: {
                    SettingsIconControlLabel(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .settingsIconControlFrame()
                .help("Delete Dock Set")
                .accessibilityLabel("Delete Dock Set")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var nativePicker: some View {
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

/// Keeps the native SwiftUI tab picker intact while giving it a real AppKit
/// scroll document whose width is based on the picker's intrinsic content.
private struct NativeHorizontalScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .automatic

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        scrollView.documentView = hostingView
        context.coordinator.hostingView = hostingView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let hostingView = context.coordinator.hostingView else { return }
        hostingView.rootView = content
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let viewportSize = scrollView.contentView.bounds.size
        hostingView.setFrameSize(NSSize(
            width: max(fittingSize.width, viewportSize.width),
            height: max(fittingSize.height, viewportSize.height)
        ))
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
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
            "Apply to Spaces",
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
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(displayGroups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.name)
                                    .font(.headline)
                                    .padding(.leading, 4)

                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 110, maximum: 140))],
                                    spacing: 12
                                ) {
                                    ForEach(group.spaces) { space in
                                        spaceCard(for: space, isDefault: isDefault)
                                    }
                                }
                            }
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

    private var displayGroups: [DockDisplaySpaceGroup] {
        Dictionary(grouping: spaceManager.availableSpaces, by: \.displayID)
            .map { displayID, spaces in
                DockDisplaySpaceGroup(
                    id: displayID,
                    name: spaces.first?.displayName ?? displayID,
                    spaces: spaces.sorted { $0.number < $1.number }
                )
            }
            .sorted { lhs, rhs in
                if lhs.id.caseInsensitiveCompare("Main") == .orderedSame { return true }
                if rhs.id.caseInsensitiveCompare("Main") == .orderedSame { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

private struct DockDisplaySpaceGroup: Identifiable {
    let id: String
    let name: String
    let spaces: [SpaceInfo]
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
            Text(spaceDisplayName(space))
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        )
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .opacity(isDimmed ? 0.5 : 1)
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
            "Dock Items",
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
                        SettingsIconControlLabel(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.regular)
                    .settingsIconControlFrame()
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
                ReorderableSettingsList(
                    items: reorderableItems,
                    rowContent: { item, context in
                        VStack(spacing: 0) {
                            DockTileRow(
                                tile: item.tile,
                                onDelete: { removeTile(id: item.tile.id) }
                            )

                            if !context.isLast {
                                Divider()
                            }
                        }
                    },
                    dragPreview: { item in
                        dockTileDragPreview(for: item.tile)
                    },
                    moveBefore: { sourceID, targetID in
                        moveTile(sourceID: sourceID, before: targetID)
                    },
                    moveToEnd: { sourceID in
                        moveTileToEnd(sourceID: sourceID)
                    }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: tiles)
            }
        }
        .alert("Could Not Read Current Dock", isPresented: $showingCurrentDockReadError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("SpaceSwitcher could not read the current Dock items.")
        }
    }

    private var reorderableItems: [ReorderableDockTile] {
        tiles.map(ReorderableDockTile.init)
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

    private func removeTile(id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            tiles.removeAll { $0.id == id }
        }
    }

    private func moveTile(sourceID: String, before targetID: String) -> Bool {
        guard let sourceUUID = UUID(uuidString: sourceID),
              let targetUUID = UUID(uuidString: targetID),
              let sourceIndex = tiles.firstIndex(where: { $0.id == sourceUUID }),
              let targetIndex = tiles.firstIndex(where: { $0.id == targetUUID }),
              sourceIndex != targetIndex else { return false }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            let movedTile = tiles.remove(at: sourceIndex)
            let destinationIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
            tiles.insert(movedTile, at: destinationIndex)
        }
        return true
    }

    private func moveTileToEnd(sourceID: String) {
        guard let sourceUUID = UUID(uuidString: sourceID),
              let sourceIndex = tiles.firstIndex(where: { $0.id == sourceUUID }),
              sourceIndex < tiles.count - 1 else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            tiles.append(tiles.remove(at: sourceIndex))
        }
    }

    private func dockTileDragPreview(for tile: DockTile) -> some View {
        DockTileRow(tile: tile, onDelete: {})
            .padding(.horizontal, SettingsComponentMetrics.listRowHorizontalPadding)
            .frame(minWidth: 320)
            .background(SettingsSectionStyle.dragPreviewBackgroundColor)
            .contentShape(.dragPreview, Rectangle())
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
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 20)
                .accessibilityLabel("Drag to rearrange")

            iconView
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)

            Text(tile.label)
                .font(.body.weight(.medium))

            Spacer()

            Button(role: .destructive, action: onDelete) {
                SettingsDestructiveIconLabel(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Remove Dock Item")
            .accessibilityLabel("Remove Dock Item")
        }
        .padding(.horizontal, SettingsComponentMetrics.listRowHorizontalPadding)
        .padding(.vertical, SettingsComponentMetrics.rowVerticalPadding)
        .frame(height: SettingsComponentMetrics.listRowHeight, alignment: .center)
        .contentShape(Rectangle())
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

private struct ReorderableDockTile: Identifiable {
    let tile: DockTile

    var id: String {
        tile.id.uuidString
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

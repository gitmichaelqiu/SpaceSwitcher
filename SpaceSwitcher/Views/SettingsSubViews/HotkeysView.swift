import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

struct HotkeysView: View {
    @ObservedObject var hotkeyManager: ContextualHotkeyManager
    @ObservedObject var spaceManager: SpaceManager
    @StateObject private var permissionManager = PermissionManager.shared

    @State private var presentedEditor: ContextualHotkey?
    @State private var hotkeyPendingDeletion: ContextualHotkey?

    var body: some View {
        SettingsContainer(.hotkeys) {
            VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionSpacing) {
                automationSection
                hotkeysSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $presentedEditor) { hotkey in
            HotkeyEditorView(
                hotkey: hotkey,
                existingHotkeys: hotkeyManager.hotkeys,
                availableSpaces: spaceManager.availableSpaces,
                onSave: save,
                onCancel: { presentedEditor = nil }
            )
        }
        .confirmationDialog(
            "Delete hotkey?",
            isPresented: Binding(
                get: { hotkeyPendingDeletion != nil },
                set: { if !$0 { hotkeyPendingDeletion = nil } }
            )
        ) {
            Button("Delete Hotkey", role: .destructive) {
                if let hotkeyPendingDeletion {
                    hotkeyManager.delete(hotkeyPendingDeletion)
                }
                hotkeyPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                hotkeyPendingDeletion = nil
            }
        }
    }

    private var automationSection: some View {
        SettingsSection("Automation") {
            SettingsRow(
                "Enable contextual hotkeys",
                requirements: automationRequirements
            ) {
                Toggle("", isOn: $hotkeyManager.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var automationRequirements: [SettingsRequirement] {
        var requirements: [SettingsRequirement] = [
            .spaceAPI(isAvailable: spaceManager.apiAvailability == .available)
        ]
        if hotkeyManager.hotkeys.contains(where: \.requiresAccessibility) {
            requirements.append(.accessibility(isGranted: permissionManager.isAccessibilityGranted))
        }
        return requirements
    }

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionContentSpacing) {
            SettingsSectionTitle("Shortcuts")
                .overlay(alignment: .trailing) {
                    SettingsIconControlButton(
                        label: "Add hotkey",
                        systemName: "plus",
                        action: addHotkey
                    )
                }

            if hotkeyManager.hotkeys.isEmpty {
                SettingsSection {
                    Text("No shortcuts")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 96)
                }
                .padding(.top, -SettingsComponentMetrics.untitledSectionTopAdjustment)
            } else {
                ReorderableSettingsList(
                    items: reorderableHotkeys,
                    rowContent: { item, context in
                        hotkeyCard(item.hotkey)
                            .padding(
                                .top,
                                context.index == 0
                                    ? -SettingsComponentMetrics.untitledSectionTopAdjustment
                                    : 0
                            )
                            .padding(
                                .bottom,
                                context.isLast ? 0 : SettingsComponentMetrics.sectionSpacing
                            )
                    },
                    dragPreview: { item in
                        hotkeyCard(item.hotkey)
                            .frame(minWidth: 420)
                    },
                    moveBefore: { sourceID, targetID in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            hotkeyManager.moveHotkey(sourceID: sourceID, before: targetID)
                        }
                    },
                    moveToEnd: { sourceID in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            _ = hotkeyManager.moveHotkeyToEnd(sourceID: sourceID)
                        }
                    }
                )
            }
        }
    }

    private var reorderableHotkeys: [ReorderableHotkey] {
        hotkeyManager.hotkeys.map(ReorderableHotkey.init)
    }

    private func hotkeyCard(_ hotkey: ContextualHotkey) -> some View {
        SettingsSection {
            hotkeyRow(hotkey)
        }
    }

    private func hotkeyRow(_ hotkey: ContextualHotkey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                HStack(spacing: 8) {
                    Text(hotkey.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(hotkey.shortcutDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if hotkeyManager.unavailableShortcutIDs.contains(hotkey.id) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("This shortcut could not be registered. It may already be in use.")
                            .accessibilityLabel("Shortcut unavailable")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        presentedEditor = hotkeyManager.duplicate(hotkey)
                    }
                }

                SettingsListItemActions(
                    isEnabled: Binding(
                        get: { hotkeyManager.hotkeys.first(where: { $0.id == hotkey.id })?.isEnabled ?? false },
                        set: { isEnabled in
                            var updated = hotkey
                            updated.isEnabled = isEnabled
                            hotkeyManager.update(updated)
                        }
                    ),
                    toggleLabel: "Enable hotkey",
                    editHelp: "Edit hotkey",
                    deleteHelp: "Delete hotkey",
                    isToggleEnabled: hotkey.keyCode != nil,
                    onEdit: { presentedEditor = hotkey },
                    onDelete: { hotkeyPendingDeletion = hotkey }
                )
            }
            .padding(.horizontal, SettingsComponentMetrics.rowHorizontalPadding)
            .padding(.vertical, SettingsComponentMetrics.rowVerticalPadding)
            .frame(minHeight: SettingsComponentMetrics.listRowHeight)

            if !hotkey.spaceActionGroups.isEmpty || hotkey.otherSpacesAction.kind != .doNothing {
                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(hotkey.spaceActionGroups) { group in
                        SettingsPreviewRow(
                            icon: "arrow.up.forward.app",
                            title: spacesTitle(for: group),
                            details: actionSummary(group.action),
                            applicationBundleIdentifier: group.action.appBundleIdentifier
                        )

                        if hotkey.spaceActionGroups.last?.id != group.id
                            || hotkey.otherSpacesAction.kind != .doNothing {
                            Divider()
                        }
                    }

                    if hotkey.otherSpacesAction.kind != .doNothing {
                        SettingsPreviewRow(
                            icon: "ellipsis.circle",
                            title: "Other Spaces",
                            details: actionSummary(hotkey.otherSpacesAction),
                            applicationBundleIdentifier: hotkey.otherSpacesAction.appBundleIdentifier
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func spacesTitle(for group: ContextualHotkeySpaceActionGroup) -> String {
        let knownSpaces = spaceManager.availableSpaces.filter { group.spaceIDs.contains($0.id) }
        let availableSpaceIDs = Set(spaceManager.availableSpaces.map(\.id))
        let unavailableNames = group.spaceIDs
            .subtracting(availableSpaceIDs)
            .map {
                String.localizedStringWithFormat(
                    NSLocalizedString("Unavailable Space (%@)", comment: "A hotkey group refers to a Space that no longer exists"),
                    String($0.prefix(8))
                )
            }
        let names = (knownSpaces.map(spaceDisplayName) + unavailableNames).sorted()
        guard !names.isEmpty else {
            return NSLocalizedString("Unassigned", comment: "Hotkey group without spaces")
        }
        return names.joined(separator: ", ")
    }

    private func actionSummary(_ action: ContextualHotkeyAction) -> String {
        guard action.kind != .doNothing else { return action.kind.title }
        let target = action.appName ?? action.appBundleIdentifier
        guard let target, !target.isEmpty else { return action.kind.title }
        return "\(action.kind.title): \(target)"
    }

    private func addHotkey() {
        presentedEditor = hotkeyManager.newHotkey(
            currentSpaceID: spaceManager.currentSpaceID,
            availableSpaces: spaceManager.availableSpaces
        )
    }

    private func save(_ hotkey: ContextualHotkey) {
        if hotkeyManager.hotkeys.contains(where: { $0.id == hotkey.id }) {
            hotkeyManager.update(hotkey)
        } else {
            hotkeyManager.add(hotkey)
        }
        presentedEditor = nil
    }
}

private struct ReorderableHotkey: Identifiable {
    let hotkey: ContextualHotkey

    var id: String { hotkey.id.uuidString }
}

private struct HotkeyEditorView: View {
    @State private var draft: ContextualHotkey
    @State private var spacePickerGroupID: UUID?
    @State private var groupPendingDeletion: UUID?
    @FocusState private var isNameFieldFocused: Bool

    let existingHotkeys: [ContextualHotkey]
    let availableSpaces: [SpaceInfo]
    let onSave: (ContextualHotkey) -> Void
    let onCancel: () -> Void

    init(
        hotkey: ContextualHotkey,
        existingHotkeys: [ContextualHotkey],
        availableSpaces: [SpaceInfo],
        onSave: @escaping (ContextualHotkey) -> Void,
        onCancel: @escaping () -> Void
    ) {
        var initialDraft = hotkey
        if initialDraft.keyCode == nil {
            initialDraft.isEnabled = false
        }
        _draft = State(initialValue: initialDraft)
        self.existingHotkeys = existingHotkeys
        self.availableSpaces = availableSpaces
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var validationError: ContextualHotkeyValidationError? {
        ContextualHotkeyValidator.validationError(for: draft, existing: existingHotkeys)
    }

    private var editorTitle: LocalizedStringKey {
        existingHotkeys.contains(where: { $0.id == draft.id }) ? "Edit Hotkey" : "Add Hotkey"
    }

    private var availableSpaceIDs: Set<String> {
        Set(availableSpaces.map(\.id))
    }

    private var availableDisplayGroups: [SpaceDisplayGroup] {
        SpaceDisplayGroup.make(from: availableSpaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorContent

            Divider()

            footerView
        }
        .frame(minWidth: 700, idealWidth: 820, minHeight: 500, idealHeight: 620)
        .confirmationDialog(
            "Remove workflow group?",
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { if !$0 { groupPendingDeletion = nil } }
            )
        ) {
            Button("Remove group", role: .destructive) {
                if let groupPendingDeletion {
                    removeSpaceGroup(groupPendingDeletion)
                }
                groupPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                groupPendingDeletion = nil
            }
        } message: {
            Text("The spaces and actions in this group will be removed.")
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editorTitle)
                .font(.title2.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionSpacing) {
                    identitySection
                    spaceActionsSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footerView: some View {
        VStack(spacing: 8) {
            if let validationError {
                SettingsValidationMessage(message: Text(validationError.message))
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.regular)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(validationError != nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var identitySection: some View {
        SettingsSection("Shortcut") {
            SettingsRow("Name") {
                TextField("", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .focused($isNameFieldFocused)
                    .accessibilityLabel("Hotkey name")
            }

            Divider()

            SettingsRow("Keyboard shortcut") {
                HotkeyRecorderControls(
                    keyCode: $draft.keyCode,
                    modifiers: $draft.modifiers,
                    onClear: clearShortcut
                )
            }
        }
    }

    private var spaceActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(draft.spaceActionGroups.enumerated()), id: \.element.id) { index, group in
                SettingsSection(
                    String(format: NSLocalizedString("Workflow Group %lld", comment: "Contextual hotkey workflow group title"), index + 1),
                    accessory: {
                        Button(role: .destructive) {
                            groupPendingDeletion = group.id
                        } label: {
                            SettingsDestructiveIconLabel(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.regular)
                        .help("Remove workflow group")
                        .accessibilityLabel("Remove workflow group")
                    }
                ) {
                    spaceSelectionRow(for: group.id)
                    Divider()
                    actionRow(
                        title: "Action",
                        action: actionBinding(forGroupID: group.id)
                    )
                }
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    draft.spaceActionGroups.append(
                        ContextualHotkeySpaceActionGroup(spaceIDs: [], action: .doNothing)
                    )
                }
            } label: {
                Label("Add workflow group", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .center)

            SettingsSection("Fallback Behavior") {
                actionRow(
                    title: "Other Spaces",
                    action: $draft.otherSpacesAction
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: draft.spaceActionGroups)
    }

    private func spaceSelectionRow(for groupID: UUID) -> some View {
        SettingsRow("Spaces") {
            if availableSpaces.isEmpty {
                Text("No spaces detected")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    spacePickerGroupID = groupID
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedSpacesTitle(for: groupID))
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(minWidth: 180, maxWidth: 280, alignment: .trailing)
                .popover(
                    isPresented: spacePickerIsPresented(for: groupID),
                    attachmentAnchor: .point(UnitPoint(x: 1, y: 0.5)),
                    arrowEdge: .bottom
                ) {
                    spacePickerPopover(for: groupID)
                }
            }
        }
    }

    private func spacePickerPopover(for groupID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(availableDisplayGroups) { displayGroup in
                        VStack(alignment: .leading, spacing: 0) {
                            if availableDisplayGroups.count > 1 {
                                Text(verbatim: displayGroup.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                            }

                            ForEach(displayGroup.spaces) { space in
                                let isSelectedHere = groupSpaceIDs(for: groupID).contains(space.id)
                                let assignedToOtherGroup = draft.spaceActionGroups.contains {
                                    $0.id != groupID && $0.spaceIDs.contains(space.id)
                                }
                                SettingsSpacePickerToggleRow(
                                    title: spaceDisplayName(space),
                                    isOn: Binding(
                                        get: { groupSpaceIDs(for: groupID).contains(space.id) },
                                        set: { setSpace(space.id, inGroup: groupID, isSelected: $0) }
                                    ),
                                    isEnabled: !assignedToOtherGroup || isSelectedHere
                                )
                            }
                        }
                    }

                    let unavailableSpaceIDs = groupSpaceIDs(for: groupID)
                        .subtracting(availableSpaceIDs)
                        .sorted()
                    if !unavailableSpaceIDs.isEmpty {
                        Divider()
                            .padding(.vertical, 4)

                        ForEach(unavailableSpaceIDs, id: \.self) { spaceID in
                            SettingsSpacePickerToggleRow(
                                title: "Unavailable Space (\(String(spaceID.prefix(8))))",
                                isOn: Binding(
                                    get: { groupSpaceIDs(for: groupID).contains(spaceID) },
                                    set: { setSpace(spaceID, inGroup: groupID, isSelected: $0) }
                                )
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 252)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(width: 220)
    }

    private func spacePickerIsPresented(for groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { spacePickerGroupID == groupID },
            set: { isPresented in
                if !isPresented, spacePickerGroupID == groupID {
                    spacePickerGroupID = nil
                }
            }
        )
    }

    private func groupSpaceIDs(for groupID: UUID) -> Set<String> {
        draft.spaceActionGroups.first(where: { $0.id == groupID })?.spaceIDs ?? []
    }

    private func selectedSpacesTitle(for groupID: UUID) -> String {
        let spaceIDs = groupSpaceIDs(for: groupID)
        var titles = availableSpaces
            .filter { spaceIDs.contains($0.id) }
            .map(spaceDisplayName)
        titles.append(contentsOf: spaceIDs.subtracting(availableSpaceIDs).sorted().map {
            "Unavailable Space (\(String($0.prefix(8))))"
        })
        return titles.isEmpty
            ? String(localized: "Choose spaces", comment: "Empty contextual hotkey space picker label")
            : titles.joined(separator: ", ")
    }

    private func setSpace(_ spaceID: String, inGroup groupID: UUID, isSelected: Bool) {
        guard let groupIndex = draft.spaceActionGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let isAlreadySelected = draft.spaceActionGroups[groupIndex].spaceIDs.contains(spaceID)
        guard isSelected != isAlreadySelected else { return }

        if isSelected {
            let assignedElsewhere = draft.spaceActionGroups.enumerated().contains {
                $0.offset != groupIndex && $0.element.spaceIDs.contains(spaceID)
            }
            guard !assignedElsewhere else { return }
            draft.spaceActionGroups[groupIndex].spaceIDs.insert(spaceID)
        } else {
            draft.spaceActionGroups[groupIndex].spaceIDs.remove(spaceID)
        }
    }

    private func actionRow(
        title: LocalizedStringResource,
        action: Binding<ContextualHotkeyAction>
    ) -> some View {
        SettingsRow(title) {
            VStack(alignment: .trailing, spacing: 6) {
                Picker("Action", selection: action.kind) {
                    Text(ContextualHotkeyActionKind.doNothing.title)
                        .tag(ContextualHotkeyActionKind.doNothing)

                    ForEach(ContextualHotkeyActionCategory.allCases) { category in
                        Section {
                            ForEach(category.actions) { kind in
                                Text(kind.title)
                                    .tag(kind)
                            }
                        } header: {
                            Text(verbatim: category.title)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Choose an action")

                if action.wrappedValue.kind != .doNothing {
                    ApplicationSelectionPicker(action: action)
                        .frame(minWidth: 220, maxWidth: 280, alignment: .trailing)
                }
            }
        }
    }

    private func actionBinding(forGroupID groupID: UUID) -> Binding<ContextualHotkeyAction> {
        Binding(
            get: {
                draft.spaceActionGroups.first(where: { $0.id == groupID })?.action ?? .doNothing
            },
            set: { newAction in
                guard let index = draft.spaceActionGroups.firstIndex(where: { $0.id == groupID }) else { return }
                draft.spaceActionGroups[index].action = newAction
            }
        )
    }

    private func removeSpaceGroup(_ groupID: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            draft.spaceActionGroups.removeAll { $0.id == groupID }
        }
        if spacePickerGroupID == groupID {
            spacePickerGroupID = nil
        }
    }

    private func clearShortcut() {
        draft.keyCode = nil
        draft.modifiers = 0
        draft.isEnabled = false
    }
}

private struct HotkeyRecorderControls: View {
    @Binding var keyCode: Int?
    @Binding var modifiers: UInt
    let onClear: () -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(isRecording ? "Press Shortcut…" : displayedShortcut)
                .foregroundColor(.secondary)
                .padding(.trailing, 8)

            Button("◉") {
                isRecording = true
            }
            .disabled(isRecording)
            .help("Record shortcut. Press Escape to cancel.")
            .accessibilityLabel(isRecording ? "Recording shortcut" : "Record shortcut")

            Button("↺", action: onClear)
                .disabled(keyCode == nil)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
        }
        .onChange(of: isRecording) { recording in
            if recording {
                startMonitoringKeys()
            } else {
                stopMonitoringKeys()
            }
        }
        .onDisappear {
            stopMonitoringKeys()
            isRecording = false
        }
    }

    private var displayedShortcut: String {
        guard let keyCode else { return NSLocalizedString("No shortcut set", comment: "Contextual hotkey without a recorded shortcut") }
        return ShortcutHelper.format(code: keyCode, modifiers: modifiers)
    }

    private func startMonitoringKeys() {
        stopMonitoringKeys()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
                return nil
            }

            keyCode = Int(event.keyCode)
            modifiers = ContextualHotkeyModifiers.normalized(UInt(event.modifierFlags.rawValue))
            isRecording = false
            return nil
        }
    }

    private func stopMonitoringKeys() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

private struct ApplicationSelectionPicker: View {
    @Binding var action: ContextualHotkeyAction
    @State private var showingApplicationPicker = false

    private var selectedAppIsAvailable: Bool {
        guard let bundleIdentifier = action.appBundleIdentifier else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
            || !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    var body: some View {
        Button {
            showingApplicationPicker.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: selectedApplicationIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(applicationLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Choose an application for this action")
        .accessibilityLabel("Choose application: \(applicationLabel)")
        .popover(
            isPresented: $showingApplicationPicker,
            attachmentAnchor: .point(UnitPoint(x: 1, y: 0.5)),
            arrowEdge: .top
        ) {
            RunningApplicationPickerPopover(
                selectedBundleIdentifier: action.appBundleIdentifier,
                includesAllAppsOption: false,
                isAllAppsSelected: false,
                onSelectAllApps: {},
                onSelectApplication: select,
                onChooseApplication: chooseApplication
            )
        }
    }

    private var selectedApplicationIcon: NSImage {
        guard let bundleIdentifier = action.appBundleIdentifier else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: applicationURL.path)
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.icon
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private var applicationLabel: String {
        guard let appName = action.appName else {
            return NSLocalizedString("Choose App…", comment: "Choose an app for a contextual hotkey")
        }
        return action.appBundleIdentifier != nil && !selectedAppIsAvailable
            ? "\(appName) (Unavailable)"
            : appName
    }

    private func select(_ name: String, bundleIdentifier: String) {
        action.appName = name
        action.appBundleIdentifier = bundleIdentifier
        showingApplicationPicker = false
    }

    private func chooseApplication() {
        showingApplicationPicker = false
        guard let window = NSApp.keyWindow else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK,
                  let url = panel.url,
                  let bundle = Bundle(url: url),
                  let bundleIdentifier = bundle.bundleIdentifier else {
                return
            }

            let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary
            let name = (info?["CFBundleDisplayName"] as? String)
                ?? (info?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            DispatchQueue.main.async {
                select(name, bundleIdentifier: bundleIdentifier)
            }
        }
    }
}

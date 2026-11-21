import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

struct HotkeysView: View {
    @ObservedObject var hotkeyManager: ContextualHotkeyManager
    @ObservedObject var spaceManager: SpaceManager

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
        } message: {
            Text("This removes the contextual hotkey and all of its Space actions.")
        }
    }

    private var automationSection: some View {
        SettingsSection("Contextual Hotkeys") {
            SettingsRow(
                "Enable contextual hotkeys",
                helperText: "This setting is independent of automatic Rules and uses the current Space on the active display.",
                requirements: [
                    .spaceAPI(isAvailable: spaceManager.apiAvailability == .available)
                ]
            ) {
                Toggle("", isOn: $hotkeyManager.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var hotkeysSection: some View {
        SettingsSection(
            "Shortcuts",
            helperText: "Each shortcut runs the action assigned to the current Space.",
            accessory: {
                Button {
                    addHotkey()
                } label: {
                    Label("Add Hotkey", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        ) {
            if hotkeyManager.hotkeys.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(hotkeyManager.hotkeys.enumerated()), id: \.element.id) { index, hotkey in
                        hotkeyRow(hotkey)
                        if index < hotkeyManager.hotkeys.count - 1 {
                            Divider()
                                .padding(.leading, SettingsComponentMetrics.rowHorizontalPadding)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No contextual hotkeys yet")
                .font(.headline)
            Text("For example, use Option–Command–O to open a different app in each Space.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(20)
    }

    private func hotkeyRow(_ hotkey: ContextualHotkey) -> some View {
        HStack(spacing: 12) {
            Button {
                presentedEditor = hotkey
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hotkey.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 10) {
                        Text(hotkey.shortcutDescription)
                            .foregroundStyle(.secondary)
                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("%lld Spaces", comment: "Number of Space mappings for a hotkey"),
                            Int64(hotkey.configuredSpaceCount)
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if hotkeyManager.unavailableShortcutIDs.contains(hotkey.id) {
                        Label(
                            "This shortcut could not be registered. It may be unavailable.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                "Enable \(hotkey.name)",
                isOn: Binding(
                    get: { hotkeyManager.hotkeys.first(where: { $0.id == hotkey.id })?.isEnabled ?? false },
                    set: { isEnabled in
                        var updated = hotkey
                        updated.isEnabled = isEnabled
                        hotkeyManager.update(updated)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(hotkey.keyCode == nil)

            Menu {
                Button("Edit Hotkey", systemImage: "pencil") {
                    presentedEditor = hotkey
                }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    presentedEditor = hotkeyManager.duplicate(hotkey)
                }
                Divider()
                Button("Delete Hotkey", systemImage: "trash", role: .destructive) {
                    hotkeyPendingDeletion = hotkey
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("Hotkey actions")
        }
        .padding(.horizontal, SettingsComponentMetrics.rowHorizontalPadding)
        .padding(.vertical, SettingsComponentMetrics.rowVerticalPadding)
        .frame(minHeight: SettingsComponentMetrics.listRowHeight)
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

private struct HotkeyEditorView: View {
    @State private var draft: ContextualHotkey
    @State private var showingSpacePicker = false

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

    private var availableSpaceIDs: Set<String> {
        Set(availableSpaces.map(\.id))
    }

    private var assignedSpaceIDs: Set<String> {
        Set(draft.spaceActions.map(\.spaceID))
    }

    private var assignedDisplayGroups: [SpaceDisplayGroup] {
        SpaceDisplayGroup.make(
            from: availableSpaces.filter { assignedSpaceIDs.contains($0.id) }
        )
    }

    private var unavailableMappings: [ContextualHotkeySpaceAction] {
        draft.spaceActions
            .filter { !availableSpaceIDs.contains($0.spaceID) }
            .sorted { $0.spaceID.localizedStandardCompare($1.spaceID) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Configure Contextual Hotkey")
                    .font(.title2.weight(.semibold))
                Text("Choose one action for each assigned Space. Your Mac will stay on its current Space while you edit.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionSpacing) {
                    identitySection
                    spaceActionsSection
                    fallbackSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Hotkey") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validationError != nil)
            }
        }
        .padding()
        .frame(minWidth: 620, idealWidth: 680, minHeight: 500, idealHeight: 560)
        .sheet(isPresented: $showingSpacePicker) {
            SpacePickerSheet(
                spaces: availableSpaces.filter { !assignedSpaceIDs.contains($0.id) },
                onSelect: { space in
                    draft.spaceActions.append(
                        ContextualHotkeySpaceAction(spaceID: space.id, action: .doNothing)
                    )
                    showingSpacePicker = false
                },
                onCancel: { showingSpacePicker = false }
            )
        }
    }

    private var identitySection: some View {
        SettingsSection("Shortcut") {
            SettingsRow("Name", warningText: nameWarningText) {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Hotkey name")
            }

            Divider()

            SettingsRow(
                "Keyboard shortcut",
                helperText: "Use at least one modifier key, such as Command or Option. Escape cancels recording.",
                warningText: shortcutWarningText
            ) {
                HotkeyRecorderControls(
                    keyCode: $draft.keyCode,
                    modifiers: $draft.modifiers,
                    onClear: clearShortcut
                )
            }

            Divider()

            SettingsRow("Enable this hotkey") {
                Toggle("", isOn: $draft.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(draft.keyCode == nil)
            }
        }
    }

    private var spaceActionsSection: some View {
        SettingsSection(
            "Space Actions",
            helperText: "Uses the current Space on the active display."
        ) {
            SettingsRow("Spaces") {
                HStack(spacing: 10) {
                    if assignedDisplayGroups.isEmpty && unavailableMappings.isEmpty {
                        Text("No Spaces assigned")
                            .foregroundStyle(.secondary)
                    }

                    Button("Add Space", systemImage: "plus") {
                        showingSpacePicker = true
                    }
                    .disabled(!availableSpaces.contains(where: { !assignedSpaceIDs.contains($0.id) }))
                }
            }

            if !assignedDisplayGroups.isEmpty || !unavailableMappings.isEmpty {
                Divider()
            }

            ForEach(Array(assignedDisplayGroups.enumerated()), id: \.element.id) { groupIndex, group in
                if assignedDisplayGroups.count > 1 {
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, SettingsComponentMetrics.sectionTitleLeadingPadding)
                        .padding(.top, groupIndex == 0 ? 0 : SettingsComponentMetrics.rowVerticalPadding)
                }

                ForEach(Array(group.spaces.enumerated()), id: \.element.id) { index, space in
                    if index > 0 {
                        Divider()
                            .padding(.leading, SettingsComponentMetrics.rowHorizontalPadding)
                    }
                    actionRow(
                        title: LocalizedStringResource(stringLiteral: spaceDisplayName(space)),
                        action: actionBinding(for: space.id),
                        onRemove: { removeSpace(space.id) }
                    )
                }

                if groupIndex < assignedDisplayGroups.count - 1 || !unavailableMappings.isEmpty {
                    Divider()
                        .padding(.leading, SettingsComponentMetrics.rowHorizontalPadding)
                }
            }

            if !unavailableMappings.isEmpty {
                ForEach(Array(unavailableMappings.enumerated()), id: \.element.id) { index, mapping in
                    if index > 0 {
                        Divider()
                            .padding(.leading, SettingsComponentMetrics.rowHorizontalPadding)
                    }
                    actionRow(
                        title: "Unavailable Space (\(String(mapping.spaceID.prefix(8))))",
                        warningText: "This Space is currently unavailable. Its mapping is preserved.",
                        action: actionBinding(for: mapping.spaceID),
                        onRemove: { removeSpace(mapping.spaceID) }
                    )
                }
            }
        }
    }

    private var fallbackSection: some View {
        SettingsSection(
            "Other Spaces",
            helperText: "Runs only when the current Space has no assigned action."
        ) {
            actionRow(
                title: "Action",
                warningText: otherSpacesWarningText,
                action: $draft.otherSpacesAction,
                onRemove: nil
            )
        }
    }

    private var nameWarningText: LocalizedStringKey? {
        guard let validationError, validationError == .missingName else { return nil }
        return LocalizedStringKey(validationError.message)
    }

    private var shortcutWarningText: LocalizedStringKey? {
        guard let validationError else { return nil }
        switch validationError {
        case .missingShortcut, .missingModifier, .shortcutInUse:
            return LocalizedStringKey(validationError.message)
        case .missingName, .missingAction, .missingApplication:
            return nil
        }
    }

    private var otherSpacesWarningText: LocalizedStringKey? {
        guard let validationError, validationError == .missingAction else { return nil }
        return LocalizedStringKey(validationError.message)
    }

    private func actionRow(
        title: LocalizedStringResource,
        warningText: LocalizedStringKey? = nil,
        action: Binding<ContextualHotkeyAction>,
        onRemove: (() -> Void)?
    ) -> some View {
        let applicationPicker = ApplicationSelectionPicker(action: action)
        let applicationNeedsSelection = action.wrappedValue.isAction && !action.wrappedValue.isConfigured
        var rowWarningText = warningText
        if rowWarningText == nil {
            if applicationNeedsSelection {
                rowWarningText = "Choose an application for this action."
            } else {
                rowWarningText = applicationPicker.unavailableApplicationWarningText
            }
        }

        return SettingsRow(title, warningText: rowWarningText) {
            HStack(spacing: 8) {
                Picker("Action", selection: action.kind) {
                    ForEach(ContextualHotkeyActionKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbolName)
                            .tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                if action.wrappedValue.kind != .doNothing {
                    applicationPicker
                        .frame(minWidth: 180, maxWidth: 280, alignment: .trailing)
                }

                if let onRemove {
                    Button(role: .destructive, action: onRemove) {
                        SettingsDestructiveIconLabel(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove Space mapping")
                }
            }
        }
    }

    private func actionBinding(for spaceID: String) -> Binding<ContextualHotkeyAction> {
        Binding(
            get: {
                draft.spaceActions.first(where: { $0.spaceID == spaceID })?.action ?? .doNothing
            },
            set: { newAction in
                guard let index = draft.spaceActions.firstIndex(where: { $0.spaceID == spaceID }) else { return }
                draft.spaceActions[index].action = newAction
            }
        )
    }

    private func removeSpace(_ spaceID: String) {
        draft.spaceActions.removeAll { $0.spaceID == spaceID }
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

private struct SpacePickerSheet: View {
    let spaces: [SpaceInfo]
    let onSelect: (SpaceInfo) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    private var filteredGroups: [SpaceDisplayGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredSpaces = spaces.filter { space in
            query.isEmpty
                || space.name.localizedCaseInsensitiveContains(query)
                || space.displayName.localizedCaseInsensitiveContains(query)
        }
        return SpaceDisplayGroup.make(from: filteredSpaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add Spaces")
                    .font(.title2.weight(.bold))
                TextField("Search Spaces", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(18)

            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 8)

                            ForEach(group.spaces) { space in
                                ApplicationPickerRow {
                                    onSelect(space)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "square")
                                            .foregroundStyle(.secondary)
                                        Text(spaceDisplayName(space))
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "plus")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if filteredGroups.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.grid.2x2")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No Spaces found")
                                .font(.headline)
                            Text("Try a different search.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                    }
                }
                .padding(14)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 380, idealHeight: 440)
    }
}

private struct ApplicationSelectionPicker: View {
    @Binding var action: ContextualHotkeyAction
    @State private var isPresented = false
    @State private var runningApplications: [RunningApplicationChoice] = []

    private var selectedAppIsAvailable: Bool {
        guard let bundleIdentifier = action.appBundleIdentifier else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
            || !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    var unavailableApplicationWarningText: LocalizedStringKey? {
        guard action.appBundleIdentifier != nil, !selectedAppIsAvailable else { return nil }
        return "Application unavailable — choose a replacement."
    }

    var body: some View {
        Button {
            loadRunningApplications()
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: selectedApplicationIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(action.appName ?? NSLocalizedString("Choose App…", comment: "Choose an app for a contextual hotkey"))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .help("Choose an application for this action")
        .accessibilityLabel(action.appName ?? "Choose an application")
        .popover(
            isPresented: $isPresented,
            attachmentAnchor: .point(UnitPoint(x: 1, y: 0.5)),
            arrowEdge: .bottom
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Target Application")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        if runningApplications.isEmpty {
                            Text("No running applications")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        } else {
                            Text("Running Applications")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)

                            ForEach(runningApplications) { app in
                                ApplicationPickerRow {
                                    select(app.name, bundleIdentifier: app.bundleIdentifier)
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(nsImage: app.icon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                                        Text(app.name)
                                            .lineLimit(1)

                                        Spacer(minLength: 0)

                                        if action.appBundleIdentifier == app.bundleIdentifier {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)

                Divider()
                    .padding(.vertical, 4)

                ApplicationPickerRow(action: chooseApplication) {
                    Label("Choose from Applications…", systemImage: "plus.app")
                }
            }
            .padding(8)
            .frame(width: 300)
            .foregroundStyle(.primary)
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

    private func select(_ name: String, bundleIdentifier: String) {
        action.appName = name
        action.appBundleIdentifier = bundleIdentifier
    }

    private func loadRunningApplications() {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        runningApplications = NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.bundleIdentifier != ownBundleIdentifier
                    && !($0.bundleIdentifier ?? "").isEmpty
            }
            .compactMap { application in
                guard let bundleIdentifier = application.bundleIdentifier else { return nil }
                return RunningApplicationChoice(
                    bundleIdentifier: bundleIdentifier,
                    name: application.localizedName ?? bundleIdentifier,
                    icon: application.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApplication() {
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

private struct RunningApplicationChoice: Identifiable {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage

    var id: String { bundleIdentifier }
}

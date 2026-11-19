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
                Text("Assign different actions to the same shortcut in different Spaces.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                helperText: "This setting is independent of automatic Rules. Uses the current Space on the active display."
            ) {
                Toggle("Enable contextual hotkeys", isOn: $hotkeyManager.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if spaceManager.apiAvailability != .available {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("DesktopRenamer SpaceAPI is unavailable. Hotkeys are temporarily inactive.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, SettingsComponentMetrics.rowHorizontalPadding)
                .padding(.bottom, 10)
            }
        }
    }

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionContentSpacing) {
            HStack(alignment: .firstTextBaseline) {
                SettingsSectionTitle(
                    "My Hotkeys",
                    helperText: "Each shortcut runs the action assigned to the current Space."
                )
                Spacer()
                Button {
                    presentedEditor = hotkeyManager.newHotkey(
                        currentSpaceID: spaceManager.currentSpaceID,
                        availableSpaces: spaceManager.availableSpaces
                    )
                } label: {
                    Label("Add Hotkey", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if hotkeyManager.hotkeys.isEmpty {
                SettingsSection {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 230)
                }
            } else {
                VStack(spacing: SettingsComponentMetrics.sectionSpacing) {
                    ForEach(hotkeyManager.hotkeys) { hotkey in
                        hotkeyRow(hotkey)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No contextual hotkeys yet")
                .font(.headline)
            Text("For example, use Option–Command–O to open a different app in each Space.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Add Hotkey", systemImage: "plus") {
                presentedEditor = hotkeyManager.newHotkey(
                    currentSpaceID: spaceManager.currentSpaceID,
                    availableSpaces: spaceManager.availableSpaces
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func hotkeyRow(_ hotkey: ContextualHotkey) -> some View {
        SettingsSection {
            HStack(spacing: 14) {
                Button {
                    presentedEditor = hotkey
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(hotkey.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 10) {
                            Text(hotkey.shortcutDescription)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Label(
                                String.localizedStringWithFormat(
                                    NSLocalizedString("%lld Spaces", comment: "Number of Space mappings for a hotkey"),
                                    Int64(hotkey.configuredSpaceCount)
                                ),
                                systemImage: "square.grid.2x2"
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        }
                        if hotkeyManager.unavailableShortcutIDs.contains(hotkey.id) {
                            Label(
                                "This shortcut could not be registered. It may be unavailable.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.system(size: 11))
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
            .padding(.horizontal, SettingsComponentMetrics.rowHorizontalPadding + 2)
            .padding(.vertical, 12)
        }
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
        _draft = State(initialValue: hotkey)
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Configure Contextual Hotkey")
                            .font(.system(size: 21, weight: .semibold))
                        Text("Choose one action for each assigned Space. Your Mac will stay on its current Space while you edit.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    identitySection
                    spaceActionsSection
                    fallbackSection

                    if let validationError {
                        Label(validationError.message, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Toggle("Enable this hotkey", isOn: $draft.isEnabled)
                    .toggleStyle(.switch)
                    .disabled(draft.keyCode == nil)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save Hotkey") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validationError != nil)
            }
            .padding(16)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 640)
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
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Hotkey name")

                HStack(spacing: 12) {
                    HotkeyRecorderButton(
                        keyCode: $draft.keyCode,
                        modifiers: $draft.modifiers
                    )
                    if draft.keyCode != nil {
                        Button("Clear") {
                            draft.keyCode = nil
                            draft.modifiers = 0
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                }

                Text("Use at least one modifier key, such as Command or Option. Escape cancels recording.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private var spaceActionsSection: some View {
        SettingsSection("Space Actions", helperText: "Uses the current Space on the active display.") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(assignedDisplayGroups) { group in
                    if assignedDisplayGroups.count > 1 {
                        Text(group.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    ForEach(group.spaces) { space in
                        actionRow(
                            title: spaceDisplayName(space),
                            detail: group.name,
                            action: actionBinding(for: space.id),
                            onRemove: { removeSpace(space.id) }
                        )
                    }
                }

                if !unavailableMappings.isEmpty {
                    Text("Unavailable Spaces")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, assignedDisplayGroups.isEmpty ? 0 : 6)
                    ForEach(unavailableMappings) { mapping in
                        actionRow(
                            title: "Unavailable Space (\(mapping.spaceID.prefix(8)))",
                            detail: "This Space is currently unavailable. Its mapping is preserved.",
                            action: actionBinding(for: mapping.spaceID),
                            onRemove: { removeSpace(mapping.spaceID) }
                        )
                    }
                }

                addSpaceMenu
                    .padding(.top, 2)
            }
            .padding(12)
        }
    }

    private var fallbackSection: some View {
        SettingsSection(
            "Other Spaces",
            helperText: "Runs only when the current Space has no assigned action."
        ) {
            actionRow(
                title: "Other Spaces",
                detail: "Fallback for known Spaces without an assigned action.",
                action: $draft.otherSpacesAction,
                onRemove: nil
            )
            .padding(12)
        }
    }

    private var addSpaceMenu: some View {
        Button {
            showingSpacePicker = true
        } label: {
            Label("Add Space", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .disabled(!availableSpaces.contains(where: { !assignedSpaceIDs.contains($0.id) }))
    }

    private func actionRow(
        title: String,
        detail: String,
        action: Binding<ContextualHotkeyAction>,
        onRemove: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove Space mapping")
                }
            }

            HStack(spacing: 10) {
                Picker("Action", selection: action.kind) {
                    ForEach(ContextualHotkeyActionKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbolName)
                            .tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 230, alignment: .leading)

                if action.wrappedValue.kind != .doNothing {
                    ApplicationSelectionMenu(action: action)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
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
}

private struct HotkeyRecorderButton: View {
    @Binding var keyCode: Int?
    @Binding var modifiers: UInt

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button {
            isRecording = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                Text(isRecording ? "Press Shortcut…" : displayedShortcut)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                if isRecording {
                    Text("Esc cancels")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 200, minHeight: 32)
        }
        .buttonStyle(.bordered)
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
        guard let keyCode else { return NSLocalizedString("Record Shortcut", comment: "Button to record a contextual hotkey") }
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
                    .font(.system(size: 18, weight: .semibold))
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)

                            ForEach(group.spaces) { space in
                                Button {
                                    onSelect(space)
                                } label: {
                                    HStack {
                                        Image(systemName: "square")
                                            .foregroundStyle(.secondary)
                                        Text(spaceDisplayName(space))
                                        Spacer()
                                        Image(systemName: "plus")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
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
                                .font(.system(size: 12))
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

private struct ApplicationSelectionMenu: View {
    @Binding var action: ContextualHotkeyAction

    private var runningApplications: [RunningApplicationChoice] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.bundleIdentifier != ownBundleIdentifier
                    && !($0.bundleIdentifier ?? "").isEmpty
            }
            .compactMap { application in
                guard let bundleIdentifier = application.bundleIdentifier else { return nil }
                return RunningApplicationChoice(
                    bundleIdentifier: bundleIdentifier,
                    name: application.localizedName ?? bundleIdentifier
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedAppIsAvailable: Bool {
        guard let bundleIdentifier = action.appBundleIdentifier else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
            || !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Menu {
                if runningApplications.isEmpty {
                    Text("No running applications")
                } else {
                    Section("Running Applications") {
                        ForEach(runningApplications) { app in
                            Button(app.name) {
                                select(app.name, bundleIdentifier: app.bundleIdentifier)
                            }
                        }
                    }
                }
                Divider()
                Button("Choose from Applications…", systemImage: "plus.square") {
                    chooseApplication()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "app")
                    Text(action.appName ?? NSLocalizedString("Choose App…", comment: "Choose an app for a contextual hotkey"))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .menuStyle(.borderlessButton)
            .help("Choose an application for this action")

            if action.appBundleIdentifier != nil && !selectedAppIsAvailable {
                Text("Application unavailable — choose a replacement.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func select(_ name: String, bundleIdentifier: String) {
        action.appName = name
        action.appBundleIdentifier = bundleIdentifier
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

    var id: String { bundleIdentifier }
}

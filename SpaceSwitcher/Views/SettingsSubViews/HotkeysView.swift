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
        SettingsSection(
            "Shortcuts",
            accessory: {
                Button {
                    addHotkey()
                } label: {
                    SettingsIconControlLabel(systemName: "plus")
                        .frame(
                            width: SettingsComponentMetrics.compactControlHeight,
                            height: SettingsComponentMetrics.compactControlHeight
                        )
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.borderless)
                .help("Add hotkey")
                .accessibilityLabel("Add hotkey")
            }
        ) {
            if hotkeyManager.hotkeys.isEmpty {
                Text("No shortcuts")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96)
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

    private func hotkeyRow(_ hotkey: ContextualHotkey) -> some View {
        HStack(spacing: 12) {
            Button {
                presentedEditor = hotkey
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hotkey.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(hotkey.shortcutDescription)
                            .foregroundStyle(.secondary)
                        if hotkeyManager.unavailableShortcutIDs.contains(hotkey.id) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .help("This shortcut could not be registered. It may already be in use.")
                                .accessibilityLabel("Shortcut unavailable")
                        }
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
            .menuIndicator(.hidden)
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
    @State private var isSpacePickerPresented = false

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

    private var assignedSpaceIDs: Set<String> {
        Set(draft.spaceActions.map(\.spaceID))
    }

    private var selectedAvailableSpaceIDs: Set<String> {
        assignedSpaceIDs.intersection(availableSpaceIDs)
    }

    private var selectedSpacesTitle: String {
        let titles = availableSpaces
            .filter { selectedAvailableSpaceIDs.contains($0.id) }
            .map(spaceDisplayName)
        return titles.isEmpty
            ? String(localized: "Choose spaces", comment: "Empty contextual hotkey space picker label")
            : titles.joined(separator: ", ")
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
            Text(editorTitle)
                .font(.title2.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionSpacing) {
                    identitySection
                    spaceActionsSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let validationError {
                Text(validationError.message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validationError != nil)
            }
        }
        .padding()
        .frame(minWidth: 620, idealWidth: 680, minHeight: 400, idealHeight: 460)
    }

    private var identitySection: some View {
        SettingsSection("Shortcut") {
            SettingsRow("Name") {
                TextField("", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
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
        SettingsSection("Space Actions") {
            SettingsRow("Spaces") {
                if availableSpaces.isEmpty {
                    Text("No spaces detected")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        isSpacePickerPresented = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedSpacesTitle)
                                .lineLimit(1)

                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 180, maxWidth: 280, alignment: .trailing)
                    .popover(
                        isPresented: $isSpacePickerPresented,
                        attachmentAnchor: .point(UnitPoint(x: 1, y: 0.5)),
                        arrowEdge: .bottom
                    ) {
                        spacePickerPopover
                    }
                }
            }

            Divider()

            ForEach(Array(assignedDisplayGroups.enumerated()), id: \.element.id) { groupIndex, group in
                if groupIndex > 0 {
                    Divider()
                }

                if assignedDisplayGroups.count > 1 {
                    Text(group.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, SettingsComponentMetrics.rowHorizontalPadding)
                        .padding(.vertical, 4)
                }

                ForEach(Array(group.spaces.enumerated()), id: \.element.id) { index, space in
                    if index > 0 {
                        Divider()
                    }
                    actionRow(
                        title: LocalizedStringResource(stringLiteral: spaceDisplayName(space)),
                        action: actionBinding(for: space.id)
                    )
                }
            }

            if !unavailableMappings.isEmpty {
                if !assignedDisplayGroups.isEmpty {
                    Divider()
                }

                ForEach(Array(unavailableMappings.enumerated()), id: \.element.id) { index, mapping in
                    if index > 0 {
                        Divider()
                    }
                    actionRow(
                        title: "Unavailable Space (\(String(mapping.spaceID.prefix(8))))",
                        action: actionBinding(for: mapping.spaceID),
                        onRemove: { removeSpace(mapping.spaceID) }
                    )
                }
            }

            Divider()
            actionRow(
                title: "Other Spaces",
                action: $draft.otherSpacesAction,
                onRemove: nil
            )
        }
    }

    private var spacePickerPopover: some View {
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
                                SettingsSpacePickerToggleRow(
                                    title: spaceDisplayName(space),
                                    isOn: Binding(
                                        get: { selectedAvailableSpaceIDs.contains(space.id) },
                                        set: { setSpace(space.id, isSelected: $0) }
                                    )
                                )
                            }
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

    private var availableDisplayGroups: [SpaceDisplayGroup] {
        SpaceDisplayGroup.make(from: availableSpaces)
    }

    private func setSpace(_ spaceID: String, isSelected: Bool) {
        let isAlreadySelected = draft.spaceActions.contains { $0.spaceID == spaceID }
        guard isSelected != isAlreadySelected else { return }

        if isSelected {
            draft.spaceActions.append(
                ContextualHotkeySpaceAction(spaceID: spaceID, action: .doNothing)
            )
        } else {
            draft.spaceActions.removeAll { $0.spaceID == spaceID }
        }
    }

    private func actionRow(
        title: LocalizedStringResource,
        action: Binding<ContextualHotkeyAction>,
        onRemove: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack {
                Text(title)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Picker("Action", selection: action.kind) {
                    ForEach(ContextualHotkeyActionKind.allCases) { kind in
                        Text(kind.title)
                            .tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                if let onRemove {
                    Button(role: .destructive, action: onRemove) {
                        SettingsDestructiveIconLabel(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove Space mapping")
                    .accessibilityLabel("Remove Space mapping")
                }
            }
            .frame(height: SettingsComponentMetrics.compactControlHeight)

            if action.wrappedValue.kind != .doNothing {
                ApplicationSelectionPicker(action: action)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: SettingsComponentMetrics.compactControlHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 4)
        .padding(.horizontal, SettingsComponentMetrics.rowHorizontalPadding)
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

private struct ApplicationSelectionPicker: View {
    @Binding var action: ContextualHotkeyAction

    private var selectedAppIsAvailable: Bool {
        guard let bundleIdentifier = action.appBundleIdentifier else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
            || !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

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
                    name: application.localizedName ?? bundleIdentifier,
                    icon: application.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Menu {
            if runningApplications.isEmpty {
                Text("No running applications")
            } else {
                Section("Running Applications") {
                    ForEach(runningApplications) { application in
                        Button {
                            select(application.name, bundleIdentifier: application.bundleIdentifier)
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: application.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                                Text(application.name)
                                    .lineLimit(1)

                                Spacer(minLength: 12)

                                if action.appBundleIdentifier == application.bundleIdentifier {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Choose from Applications…", systemImage: "plus.square") {
                chooseApplication()
            }
        } label: {
            HStack(spacing: 8) {
                Spacer(minLength: 0)

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(.primary)
        .help("Choose an application for this action")
        .accessibilityLabel("Choose application: \(applicationLabel)")
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

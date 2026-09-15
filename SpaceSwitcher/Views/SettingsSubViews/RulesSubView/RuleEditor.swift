import SwiftUI
import UniformTypeIdentifiers

struct RuleEditor: View {
    private let initialRule: AppRule
    @State private var workingRule: AppRule
    let availableSpaces: [SpaceInfo]
    let onSave: (AppRule) -> Void
    let onCancel: () -> Void
    @State private var runningApps: [(name: String, id: String, icon: NSImage)] = []
    @State private var showingLegend = false
    @State private var showingApplicationPicker = false
    @State private var groupPendingDeletion: UUID?
    
    init(rule: AppRule, availableSpaces: [SpaceInfo], onSave: @escaping (AppRule) -> Void, onCancel: @escaping () -> Void) {
        self.initialRule = rule
        self._workingRule = State(wrappedValue: rule)
        self.availableSpaces = availableSpaces
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            appSelectorHeader
                .zIndex(1)

            Divider()
            
            editorContent
            
            Divider()
            
            footerView
        }
        .frame(minWidth: 700, idealWidth: 820, minHeight: 500, idealHeight: 620)
        .onAppear {
            // Sheets can reuse their content between presentations. Always start
            // from the rule that was selected for this presentation.
            workingRule = initialRule
            loadRunningApps()
        }
        .confirmationDialog(
            "Remove Workflow Group?",
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { groupPendingDeletion = nil }
                }
            )
        ) {
            Button("Remove Group", role: .destructive) {
                if let groupID = groupPendingDeletion {
                    removeGroup(id: groupID)
                }
                groupPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                groupPendingDeletion = nil
            }
        } message: {
            Text("The spaces and actions in this workflow group will be removed.")
        }
    }
    
    // MARK: - Components
    
    private var appSelectorHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            applicationPicker

            Spacer()

            Button {
                showingLegend.toggle()
            } label: {
                Label(
                    "Action Definitions",
                    systemImage: "info.circle"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Action Definitions")
            .popover(isPresented: $showingLegend, arrowEdge: .top) {
                actionDefinitionsPopover
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var applicationPicker: some View {
        if runningApps.isEmpty {
            Button(action: pickOtherApp) {
                applicationPickerLabel
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .frame(width: 300, alignment: .leading)
            .help("Choose an application")
        } else {
            Button {
                showingApplicationPicker.toggle()
            } label: {
                applicationPickerLabel
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .frame(width: 300, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .popover(isPresented: $showingApplicationPicker, arrowEdge: .top) {
                runningApplicationsPopover
            }
        }
    }

    private var runningApplicationsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Running Applications")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(runningApps, id: \.id) { app in
                        Button {
                            selectApp(name: app.name, id: app.id)
                            showingApplicationPicker = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .cornerRadius(4)

                                Text(app.name)
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()
                .padding(.vertical, 6)

            Button {
                showingApplicationPicker = false
                pickOtherApp()
            } label: {
                Label("Choose from Applications...", systemImage: "plus.app")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .padding(8)
        .frame(width: 300)
    }

    private var applicationPickerLabel: some View {
        HStack(spacing: 12) {
            selectedAppIcon
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedApplicationName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(workingRule.appBundleID.isEmpty ? "Choose an application" : workingRule.appBundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !runningApps.isEmpty {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(workingRule.appBundleID.isEmpty ? "Choose an application" : selectedApplicationName)
    }

    private var selectedApplicationName: String {
        guard !workingRule.appBundleID.isEmpty else { return "Choose an application" }

        if let bundle = selectedApplicationURL.flatMap(Bundle.init(url:)) {
            let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary
            if let displayName = info?["CFBundleDisplayName"] as? String, !displayName.isEmpty {
                return displayName
            }
            if let name = info?["CFBundleName"] as? String, !name.isEmpty {
                return name
            }
        }

        return workingRule.appName.isEmpty ? workingRule.appBundleID : workingRule.appName
    }

    private var selectedApplicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)
    }

    @ViewBuilder
    private var selectedAppIcon: some View {
        if let path = selectedApplicationURL?.path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var editorContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach($workingRule.groups) { $group in
                    let index = workingRule.groups.firstIndex(where: { $0.id == group.id }) ?? 0
                    SettingsSection(
                        String(format: NSLocalizedString("Workflow Group %lld", comment: ""), index + 1),
                        accessory: {
                            Button(role: .destructive) {
                                groupPendingDeletion = group.id
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.regular)
                            .help("Remove Workflow Group")
                            .accessibilityLabel("Remove Workflow Group")
                        }) {
                        SpaceConditionRow(
                            group: $group,
                            availableSpaces: availableSpaces
                        )

                        if !group.actions.isEmpty {
                            Divider()
                        }

                        ActionListRows(actions: $group.actions)

                        AddActionRow {
                            actionMenu(for: group.id)
                        }
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        workingRule.groups.append(RuleGroup(targetSpaceIDs: [], actions: []))
                    }
                } label: {
                    Label("Add Workflow Group", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .center)

                SettingsSection("Fallback Behavior", helperText: "Actions used when no workflow group matches the current space.") {
                    if workingRule.elseActions.isEmpty {
                        Label("No fallback actions", systemImage: "arrow.turn.down.right")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    } else {
                        ActionListRows(actions: $workingRule.elseActions)
                    }

                    AddActionRow {
                        actionMenu { action in
                            withAnimation {
                                workingRule.elseActions.append(ActionItem(action))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.25), value: workingRule.groups)
    }
    
    private var footerView: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .controlSize(.large)
                .keyboardShortcut(.escape, modifiers: [])
            
            Spacer()
            
            Button("Save Rule") {
                onSave(workingRule)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(validationMessage != nil)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func addActionToGroup(id: UUID, action: WindowAction) {
        guard let index = workingRule.groups.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            workingRule.groups[index].actions.append(ActionItem(action))
        }
    }
    
    @ViewBuilder private func actionMenu(for id: UUID) -> some View {
        actionMenu { action in
            addActionToGroup(id: id, action: action)
        }
    }

    @ViewBuilder private func actionMenu(addAction: @escaping (WindowAction) -> Void) -> some View {
        Button { addAction(.show) } label: {
            Label("Show", systemImage: "eye")
        }
        Button { addAction(.restore) } label: {
            Label("Restore", systemImage: "arrow.uturn.backward")
        }
        Button { addAction(.hide) } label: {
            Label("Hide", systemImage: "eye.slash")
        }
        Button { addAction(.minimize) } label: {
            Label("Minimize", systemImage: "arrow.down.right.and.arrow.up.left")
        }
        Button { addAction(.bringToFront) } label: {
            Label("Bring to Front", systemImage: "arrow.up.forward.app")
        }
        Divider()
        Button {
            addAction(.hotkey(keyCode: -1, modifiers: 0, restoreWindow: false, waitFrontmost: true))
        } label: {
            Label("App Shortcut...", systemImage: "app")
        }
        Button {
            addAction(.globalHotkey(keyCode: -1, modifiers: 0))
        } label: {
            Label("System Shortcut...", systemImage: "globe")
        }
    }

    private func removeGroup(id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            workingRule.groups.removeAll { $0.id == id }
        }
    }

    private var validationMessage: LocalizedStringKey? {
        if workingRule.appBundleID.isEmpty {
            return "Choose an application before saving."
        }

        if workingRule.groups.contains(where: { $0.targetSpaceIDs.isEmpty }) {
            return "Every workflow group must target at least one space."
        }

        if workingRule.groups.contains(where: { $0.actions.isEmpty }) {
            return "Every workflow group must contain at least one action."
        }

        let assignedSpaceIDs = workingRule.groups.flatMap(\.targetSpaceIDs)
        if Set(assignedSpaceIDs).count != assignedSpaceIDs.count {
            return "Each space can belong to only one workflow group."
        }

        let allActions = workingRule.groups.flatMap(\.actions) + workingRule.elseActions
        if allActions.isEmpty {
            return "Add at least one action before saving."
        }

        if allActions.contains(where: { action in
            switch action.value {
            case .hotkey(let keyCode, _, _, _), .globalHotkey(let keyCode, _):
                return keyCode < 0
            default:
                return false
            }
        }) {
            return "Record every shortcut before saving."
        }

        return nil
    }
    
    private func selectApp(name: String, id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            workingRule.appName = name
            workingRule.appBundleID = id
        }
    }
    
    private func pickOtherApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let b = Bundle(url: url)
                let id = b?.bundleIdentifier ?? ""
                let name = applicationName(for: b, fallback: url.deletingPathExtension().lastPathComponent)
                if !id.isEmpty {
                    DispatchQueue.main.async {
                        self.selectApp(name: name, id: id)
                    }
                }
            }
        }
    }

    private func applicationName(for bundle: Bundle?, fallback: String) -> String {
        let info = bundle?.localizedInfoDictionary ?? bundle?.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? fallback
    }
    
    private func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        self.runningApps = apps.map { (
            name: $0.localizedName ?? "Unknown",
            id: $0.bundleIdentifier ?? "",
            icon: $0.icon ?? NSImage()
        ) }.sorted { $0.name < $1.name }
    }
    
    private var actionDefinitionsPopover: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Action Definitions")
                    .font(.headline)

                legendItem(name: "Show", desc: "Forcefully unhide and unminimize the application, regardless of its previous state.")
                legendItem(name: "Restore", desc: "Intelligent reversal. Only unhide and unminimize if SpaceSwitcher was the one that hid it earlier.")
                legendItem(name: "Hide", desc: "Hide the application.")
                legendItem(name: "Minimize", desc: "Minimize all windows of the application.")
                legendItem(name: "Front", desc: "Activate the application and bring its windows to the foreground.")
            }
            .padding(16)
        }
        .frame(width: 300, height: 360)
    }
    
    @ViewBuilder
    private func legendItem(name: LocalizedStringKey, desc: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: .rect(cornerRadius: 4))
            
            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
    }
}

// MARK: - Subviews

struct SpaceConditionRow: View {
    @Binding var group: RuleGroup
    let availableSpaces: [SpaceInfo]

    private var selectedSpaces: [SpaceInfo] {
        availableSpaces.filter { group.targetSpaceIDs.contains($0.id) }
    }

    private var selectedSpacesTitle: String {
        if selectedSpaces.isEmpty { return "Choose spaces" }
        return selectedSpaces.map { $0.name.isEmpty ? "Space \($0.number)" : $0.name }.joined(separator: ", ")
    }
    
    var body: some View {
        SettingsRow("Spaces") {
            if availableSpaces.isEmpty {
                Text("No spaces detected")
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(availableSpaces) { space in
                        Toggle(
                            space.name.isEmpty ? "Space \(space.number)" : space.name,
                            isOn: Binding(
                                get: { group.targetSpaceIDs.contains(space.id) },
                                set: { isSelected in
                                    if isSelected {
                                        group.targetSpaceIDs.insert(space.id)
                                    } else {
                                        group.targetSpaceIDs.remove(space.id)
                                    }
                                }
                            )
                        )
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedSpacesTitle)
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(minWidth: 180, maxWidth: 280, alignment: .trailing)
            }
        }
    }
}

struct ActionListRows: View {
    @Binding var actions: [ActionItem]

    private var reorderableItems: [ReorderableActionItem] {
        actions.map(ReorderableActionItem.init)
    }

    var body: some View {
        ReorderableSettingsList(
            items: reorderableItems,
            rowContent: { item, context in
                VStack(spacing: 0) {
                    ActionRowContent(
                        index: context.index,
                        item: actionBinding(for: item),
                        onDelete: { removeAction(id: item.action.id) }
                    )
                    .padding(.horizontal, 12)

                    if !context.isLast {
                        Divider().padding(.leading, 46)
                    }
                }
            },
            dragPreview: { item in
                actionDragPreview(for: item.action)
            },
            moveBefore: { sourceID, targetID in
                moveAction(sourceID: sourceID, before: targetID)
            },
            moveToEnd: { sourceID in
                moveActionToEnd(sourceID: sourceID)
            }
        )
    }

    private func actionBinding(for item: ReorderableActionItem) -> Binding<ActionItem> {
        Binding(
            get: {
                actions.first(where: { $0.id == item.action.id }) ?? item.action
            },
            set: { updatedItem in
                guard let index = actions.firstIndex(where: { $0.id == item.action.id }) else { return }
                actions[index] = updatedItem
            }
        )
    }

    private func removeAction(id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            actions.removeAll { $0.id == id }
        }
    }

    private func moveAction(sourceID: String, before targetID: String) -> Bool {
        guard let sourceUUID = UUID(uuidString: sourceID),
              let targetUUID = UUID(uuidString: targetID),
              let sourceIndex = actions.firstIndex(where: { $0.id == sourceUUID }),
              let targetIndex = actions.firstIndex(where: { $0.id == targetUUID }),
              sourceIndex != targetIndex else { return false }

        withAnimation(.easeInOut(duration: 0.2)) {
            let movedAction = actions.remove(at: sourceIndex)
            let destinationIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
            actions.insert(movedAction, at: destinationIndex)
        }
        return true
    }

    private func moveActionToEnd(sourceID: String) {
        guard let sourceUUID = UUID(uuidString: sourceID),
              let sourceIndex = actions.firstIndex(where: { $0.id == sourceUUID }),
              sourceIndex < actions.count - 1 else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            actions.append(actions.remove(at: sourceIndex))
        }
    }

    private func actionDragPreview(for item: ActionItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Label {
                Text(verbatim: item.value.localizedString)
            } icon: {
                Image(systemName: actionIcon(for: item.value))
            }
            .font(.body)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 320, alignment: .leading)
        .contentShape(.dragPreview, Rectangle())
    }

    private func actionIcon(for action: WindowAction) -> String {
        switch action {
        case .show: return "eye"
        case .restore: return "arrow.uturn.backward"
        case .hide: return "eye.slash"
        case .minimize: return "arrow.down.right.and.arrow.up.left"
        case .bringToFront: return "arrow.up.forward.app"
        case .hotkey, .globalHotkey: return "keyboard"
        }
    }
}

private struct ReorderableActionItem: Identifiable {
    let action: ActionItem

    var id: String {
        action.id.uuidString
    }
}


struct AddActionRow<Content: View>: View {
    @ViewBuilder let menuContent: Content
    
    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack {
                Menu {
                    menuContent
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Action Content

struct ActionRowContent: View {
    let index: Int
    @Binding var item: ActionItem
    let onDelete: () -> Void
    
    @State private var isRecording = false
    @State private var recordingMonitor: Any?
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 20)
                .accessibilityLabel("Drag to rearrange")

            Text("\(index + 1)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)

            Group {
                switch item.value {
                case .globalHotkey(let code, let mods):
                    HStack(spacing: 8) {
                        Label("System Shortcut", systemImage: "globe")
                            .font(.subheadline)

                        ModifierMenu(modifiers: mods) { newModifiers in
                            item.value = .globalHotkey(keyCode: code, modifiers: newModifiers)
                        }

                        KeyCaptureButton(keyCode: code) { newCode in
                            item.value = .globalHotkey(keyCode: newCode, modifiers: mods)
                        }
                    }

                case .hotkey(let code, let mods, _, _):
                    HStack(spacing: 8) {
                        Label("App Shortcut", systemImage: "app")
                            .font(.subheadline)
                        
                        Button(action: startRecording) {
                            if isRecording {
                                Label("Recording...", systemImage: "record.circle")
                                    .foregroundStyle(.red)
                            } else {
                                Label(
                                    code == -1 ? "Record Shortcut" : ShortcutHelper.format(code: code, modifiers: mods),
                                    systemImage: "keyboard"
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        HotkeyOptionsMenu(
                            restoreWindow: Binding(
                                get: {
                                    if case .hotkey(_, _, let restoreWindow, _) = item.value {
                                        return restoreWindow
                                    }
                                    return false
                                },
                                set: { restoreWindow in
                                    updateHotkey(restoreWindow: restoreWindow, waitFrontmost: nil)
                                }
                            ),
                            waitFrontmost: Binding(
                                get: {
                                    if case .hotkey(_, _, _, let waitFrontmost) = item.value {
                                        return waitFrontmost
                                    }
                                    return true
                                },
                                set: { waitFrontmost in
                                    updateHotkey(restoreWindow: nil, waitFrontmost: waitFrontmost)
                                }
                            )
                        )
                    }

                default:
                    Label(item.value.localizedString, systemImage: actionIcon)
                        .font(.body)
                }
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .help("Remove Action")
            .accessibilityLabel("Remove Action")
        }
        .frame(minHeight: 28, alignment: .center)
        .onDisappear(perform: stopRecording)
    }
    
    private func updateHotkey(restoreWindow: Bool?, waitFrontmost: Bool?) {
        guard case .hotkey(let keyCode, let modifiers, let currentRestoreWindow, let currentWaitFrontmost) = item.value else { return }
        let newWaitFrontmost = waitFrontmost ?? currentWaitFrontmost
        item.value = .hotkey(
            keyCode: keyCode,
            modifiers: modifiers,
            restoreWindow: newWaitFrontmost ? false : (restoreWindow ?? currentRestoreWindow),
            waitFrontmost: newWaitFrontmost
        )
    }

    private var actionIcon: String {
        switch item.value {
        case .show: return "eye"
        case .restore: return "arrow.uturn.backward"
        case .hide: return "eye.slash"
        case .minimize: return "arrow.down.right.and.arrow.up.left"
        case .bringToFront: return "arrow.up.forward.app"
        case .hotkey, .globalHotkey: return "keyboard"
        }
    }
    
    private func startRecording() {
        stopRecording()
        isRecording = true

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }

            if event.keyCode == 53 {
                isRecording = false
                stopRecording()
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            let code = Int(event.keyCode)
            if case .hotkey(_, _, let restoreWindow, let waitFrontmost) = self.item.value {
                self.item.value = .hotkey(
                    keyCode: code,
                    modifiers: UInt(mods),
                    restoreWindow: restoreWindow,
                    waitFrontmost: waitFrontmost
                )
            }
            isRecording = false
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
        isRecording = false
    }
}

struct ModifierMenu: View {
    let modifiers: UInt
    let onChange: (UInt) -> Void

    var body: some View {
        Menu {
            Toggle("Command (⌘)", isOn: binding(for: .command))
            Toggle("Shift (⇧)", isOn: binding(for: .shift))
            Toggle("Option (⌥)", isOn: binding(for: .option))
            Toggle("Control (⌃)", isOn: binding(for: .control))
        } label: {
            Label(summary, systemImage: "command")
        }
        .menuStyle(.borderlessButton)
        .help("Choose Shortcut Modifiers")
    }

    private var summary: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        let symbols = [
            (NSEvent.ModifierFlags.command, "⌘"),
            (.shift, "⇧"),
            (.option, "⌥"),
            (.control, "⌃")
        ]
        let selected = symbols.compactMap { flags.contains($0.0) ? $0.1 : nil }
        return selected.isEmpty ? "No Modifiers" : selected.joined()
    }

    private func binding(for flag: NSEvent.ModifierFlags) -> Binding<Bool> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: modifiers).contains(flag) },
            set: { isEnabled in
                var updated = NSEvent.ModifierFlags(rawValue: modifiers)
                if isEnabled {
                    updated.insert(flag)
                } else {
                    updated.remove(flag)
                }
                onChange(updated.rawValue)
            }
        )
    }
}

struct HotkeyOptionsMenu: View {
    @Binding var restoreWindow: Bool
    @Binding var waitFrontmost: Bool

    var body: some View {
        Menu {
            Toggle("Wait for App to Be Frontmost", isOn: $waitFrontmost)
            Toggle("Restore Previous App", isOn: $restoreWindow)
                .disabled(waitFrontmost)
        } label: {
            Label("Shortcut Options", systemImage: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .help("Shortcut Options")
    }
}

struct KeyCaptureButton: View {
    let keyCode: Int
    let onUpdate: (Int) -> Void
    @State private var isListening = false
    
    var body: some View {
        Button {
            isListening = true
        } label: {
            Label(
                isListening ? "Press a Key" : (keyCode == -1 ? "Record Key" : displayString),
                systemImage: isListening ? "record.circle" : "keyboard"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Record Shortcut")
        .overlay(
            Group {
                if isListening {
                    KeyReceiver { event in
                        if event.keyCode == 53 {
                            isListening = false
                            return
                        }
                        let code = Int(event.keyCode)
                        onUpdate(code)
                        isListening = false
                    }
                    .frame(width: 0, height: 0)
                }
            }
        )
    }
    
    var displayString: String {
        if keyCode == -1 { return "-" }
        return ShortcutHelper.keyString(for: keyCode) ?? "?"
    }
}

struct KeyReceiver: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: KeyView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
    
    class KeyView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }
    }
}

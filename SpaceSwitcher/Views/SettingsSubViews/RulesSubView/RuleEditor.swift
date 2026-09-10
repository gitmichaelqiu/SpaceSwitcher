import SwiftUI
import UniformTypeIdentifiers

struct RuleEditor: View {
    @State private var workingRule: AppRule
    let availableSpaces: [SpaceInfo]
    let onSave: (AppRule) -> Void
    let onCancel: () -> Void
    @State private var runningApps: [(name: String, id: String, icon: NSImage)] = []
    @State private var showingLegend = false
    @State private var legendWidth: CGFloat = 260
    @State private var legendDragStartWidth: CGFloat?
    
    init(rule: AppRule, availableSpaces: [SpaceInfo], onSave: @escaping (AppRule) -> Void, onCancel: @escaping () -> Void) {
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
            
            mainSplitView
            
            Divider()
            
            footerView
        }
        .frame(minWidth: 700, idealWidth: 820, minHeight: 500, idealHeight: 620)
        .onAppear { loadRunningApps() }
    }
    
    // MARK: - Components
    
    private var appSelectorHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            Menu {
                if !runningApps.isEmpty {
                    Section("Running Applications") {
                        ForEach(runningApps, id: \.id) { app in
                            Button { selectApp(name: app.name, id: app.id) } label: {
                                HStack {
                                    Image(nsImage: app.icon)
                                    Text(app.name)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Choose from Applications...") { pickOtherApp() }
            } label: {
                HStack(spacing: 12) {
                    selectedAppIcon
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Application")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(workingRule.appBundleID.isEmpty ? "Select Application" : workingRule.appName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(workingRule.appBundleID.isEmpty ? "No selection" : workingRule.appBundleID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            Button {
                withAnimation(.easeInOut(duration: 0.35)) {
                    showingLegend.toggle()
                }
            } label: {
                Label(
                    showingLegend ? "Hide Definitions" : "Action Definitions",
                    systemImage: showingLegend ? "info.circle.fill" : "info.circle"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var selectedAppIcon: some View {
        if !workingRule.appBundleID.isEmpty,
           let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
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
    
    private var mainSplitView: some View {
        HStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    // --- WORKFLOW GROUPS ---
                    ForEach(Array(workingRule.groups.enumerated()), id: \.element.id) { index, group in
                        SettingsSection("Workflow Group \(index + 1)", accessory: {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                removeGroup(id: group.id)
                            }
                            .buttonStyle(.borderless)
                        }) {
                            SpaceConditionRow(
                                group: $workingRule.groups[index],
                                availableSpaces: availableSpaces
                            )

                            ActionListRows(actions: $workingRule.groups[index].actions)

                            AddActionRow {
                                actionMenu(for: group.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // --- ADD GROUP BUTTON ---
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            workingRule.groups.append(RuleGroup(targetSpaceIDs: [], actions: []))
                        }
                    } label: {
                        Label("Add Workflow Group", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .center)

                    // --- FALLBACK SECTION ---
                    SettingsSection("Fallback Behavior", helperText: "Actions used when no workflow group matches the current space.") {
                        if workingRule.elseActions.isEmpty {
                            Label("No fallback actions", systemImage: "arrow.turn.down.right")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
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
                    .padding(.bottom, 4)
                }
                .padding(12)
            }
            .animation(.easeInOut(duration: 0.35), value: workingRule.groups)
            .background(Color.clear)
            
            // Custom Draggable Divider & Sidebar
            if showingLegend {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1)
                    .overlay(
                        Color.clear
                            .frame(width: 8)
                            .contentShape(Rectangle())
                    )
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() }
                        else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let delta = value.translation.width
                                let startWidth = legendDragStartWidth ?? legendWidth
                                legendDragStartWidth = startWidth
                                let newWidth = startWidth - delta
                                legendWidth = max(200, min(400, newWidth))
                            }
                            .onEnded { _ in legendDragStartWidth = nil }
                    )
                
                legendSidebar
                    .frame(width: legendWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showingLegend)
    }
    
    private var footerView: some View {
        HStack(spacing: 12) {
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 320, alignment: .leading)
            }

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
            Label("App Shortcut...", systemImage: "keyboard")
        }
        Button {
            addAction(.globalHotkey(keyCode: -1, modifiers: 0))
        } label: {
            Label("Global Shortcut...", systemImage: "globe")
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
                let name = (b?.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                if !id.isEmpty {
                    DispatchQueue.main.async {
                        self.selectApp(name: name, id: id)
                    }
                }
            }
        }
    }
    
    private func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        self.runningApps = apps.map { (
            name: $0.localizedName ?? "Unknown",
            id: $0.bundleIdentifier ?? "",
            icon: $0.icon ?? NSImage()
        ) }.sorted { $0.name < $1.name }
    }
    
    @ViewBuilder
    private var legendSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Action Definitions")
                    .font(.system(size: 13, weight: .bold))
            }
            .padding(.top, 20)
            
            Divider()
            
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    legendItem(name: "Show", desc: "Forcefully unhide and unminimize the application, regardless of its previous state.")
                    legendItem(name: "Restore", desc: "Intelligent reversal. Only unhide and unminimize if SpaceSwitcher was the one that hid it earlier.")
                    legendItem(name: "Hide", desc: "Hide the application.")
                    legendItem(name: "Minimize", desc: "Minimize all windows of the application.")
                    legendItem(name: "Front", desc: "Activate the application and bring its windows to the foreground.")
                }
                .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
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
                        let isSelected = group.targetSpaceIDs.contains(space.id)
                        Button {
                            if isSelected {
                                group.targetSpaceIDs.remove(space.id)
                            } else {
                                group.targetSpaceIDs.insert(space.id)
                            }
                        } label: {
                            Label(
                                space.name.isEmpty ? "Space \(space.number)" : space.name,
                                systemImage: isSelected ? "checkmark" : "circle"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedSpacesTitle)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
    @State private var draggingItem: ActionItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(actions) { item in
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    ActionRowContent(
                        index: actions.firstIndex(where: { $0.id == item.id }) ?? 0,
                        item: binding(for: item),
                        onDelete: {
                            withAnimation {
                                actions.removeAll { $0.id == item.id }
                            }
                        }
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(draggingItem?.id == item.id ? Color.accentColor.opacity(0.08) : Color.clear)
                }
                .onDrag {
                    self.draggingItem = item
                    return NSItemProvider(object: item.id.uuidString as NSString)
                } preview: {
                    // Return an empty/clear view to hide the ghost row that follows the cursor
                    Color.clear.frame(width: 1, height: 1)
                }
                .onDrop(of: [.text], delegate: ActionDropDelegate(item: item, actions: $actions, draggingItem: $draggingItem))
            }
        }
    }
    
    private func binding(for item: ActionItem) -> Binding<ActionItem> {
        guard let index = actions.firstIndex(where: { $0.id == item.id }) else {
            return .constant(item)
        }
        return $actions[index]
    }
}

struct ActionDropDelegate: DropDelegate {
    let item: ActionItem
    @Binding var actions: [ActionItem]
    @Binding var draggingItem: ActionItem?

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem,
              draggingItem.id != item.id,
              let from = actions.firstIndex(where: { $0.id == draggingItem.id }),
              let to = actions.firstIndex(where: { $0.id == item.id })
        else { return }

        if actions[to].id != draggingItem.id {
            withAnimation(.snappy(duration: 0.2)) {
                actions.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
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
                .tint(.accentColor)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.2))
                
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                
                Group {
                    switch item.value {
                    case .globalHotkey(let code, let mods):
                        HStack(spacing: 8) {
                            ModifierMenu(modifiers: mods) { newModifiers in
                                item.value = .globalHotkey(keyCode: code, modifiers: newModifiers)
                            }
                            
                            KeyCaptureButton(keyCode: code) { newCode in
                                item.value = .globalHotkey(keyCode: newCode, modifiers: mods)
                            }
                        }
                        
                    case .hotkey(let code, let mods, _, _):
                        HStack(spacing: 8) {
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
                
                Button("Remove Action", systemImage: "trash", role: .destructive, action: onDelete)
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .help("Remove Action")
            }
            
        }
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
            Toggle("Wait for Application", isOn: $waitFrontmost)
            Toggle("Restore Previous Application", isOn: $restoreWindow)
                .disabled(waitFrontmost)
        } label: {
            Label("Options", systemImage: "gearshape")
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

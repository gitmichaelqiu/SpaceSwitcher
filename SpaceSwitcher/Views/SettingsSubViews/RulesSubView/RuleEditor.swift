import SwiftUI
import UniformTypeIdentifiers

struct RuleEditor: View {
    @State private var workingRule: AppRule
    let availableSpaces: [SpaceInfo]
    let onSave: (AppRule) -> Void
    let onCancel: () -> Void
    @State private var runningApps: [(name: String, id: String, icon: NSImage)] = []
    
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
            
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 12)
                    
                    // --- WORKFLOW GROUPS ---
                    ForEach(Array(workingRule.groups.enumerated()), id: \.element.id) { index, group in
                        VStack(alignment: .leading, spacing: 0) {
                            SpaceConditionRow(
                                groupIndex: index,
                                group: $workingRule.groups[index],
                                availableSpaces: availableSpaces,
                                onRemove: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        _ = workingRule.groups.remove(at: index)
                                    }
                                }
                            )
                            
                            ActionListRows(actions: $workingRule.groups[index].actions)
                            
                            AddActionRow {
                                addActionToGroup(index: index, action: .show)
                            } menuContent: {
                                actionMenu(for: index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4) as Color)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.regularMaterial)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                }
                
                // --- ADD GROUP BUTTON ---
                Section {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            workingRule.groups.append(RuleGroup(targetSpaceIDs: [], actions: []))
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Workflow Group")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.accentColor.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.accentColor.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                
                // --- FALLBACK SECTION ---
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Fallback Behavior")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                            Text("Default")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.02))
                        
                        Divider().opacity(0.3)
                        
                        if workingRule.elseActions.isEmpty {
                            HStack {
                                Spacer()
                                Text("No automatic actions")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .italic()
                                Spacer()
                            }
                            .padding(16)
                        } else {
                            ForEach(Array(workingRule.elseActions.enumerated()), id: \.element.id) { i, item in
                                VStack(spacing: 0) {
                                    ActionRowContent(
                                        index: i,
                                        item: $workingRule.elseActions[i],
                                        onDelete: {
                                            withAnimation {
                                                workingRule.elseActions = workingRule.elseActions.enumerated()
                                                    .filter { $0.offset != i }
                                                    .map { $0.element }
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    
                                    if i < workingRule.elseActions.count - 1 {
                                        Divider().padding(.leading, 32).opacity(0.2)
                                    }
                                }
                            }
                        }
                        
                        Divider().opacity(0.3)
                        
                        HStack {
                            Menu {
                                Button("Show") { withAnimation { workingRule.elseActions.append(ActionItem(.show)) } }
                                Button("Hide") { withAnimation { workingRule.elseActions.append(ActionItem(.hide)) } }
                                Button("Minimize") { withAnimation { workingRule.elseActions.append(ActionItem(.minimize)) } }
                            } label: {
                                Label("Add Action", systemImage: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .menuStyle(.borderlessButton)
                            .foregroundColor(.accentColor)
                            .fixedSize()
                            Spacer()
                        }
                        .padding(8)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4) as Color)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.regularMaterial)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                .padding(.vertical, 8)
            }
            .animation(.easeInOut(duration: 0.2), value: workingRule.groups)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            footerView
        }
        .frame(width: 600, height: 500)
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
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.05), radius: 2)
                    
                    if !workingRule.appBundleID.isEmpty, let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(10)
                    }
                }
                .frame(width: 54, height: 54)
            }
            .menuStyle(.borderlessButton)
            
            // Text Info
            VStack(alignment: .leading, spacing: 2) {
                Text(workingRule.appBundleID.isEmpty ? "Select Application" : workingRule.appName)
                    .font(.system(size: 18, weight: .bold))
                
                Text(workingRule.appBundleID.isEmpty ? "No selection" : workingRule.appBundleID)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
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
            .disabled(workingRule.appBundleID.isEmpty)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func addActionToGroup(index: Int, action: WindowAction) {
        withAnimation(.easeInOut(duration: 0.2)) {
            workingRule.groups[index].actions.append(ActionItem(action))
        }
    }
    
    @ViewBuilder private func actionMenu(for index: Int) -> some View {
        Button("Show") { addActionToGroup(index: index, action: .show) }
        Button("Hide") { addActionToGroup(index: index, action: .hide) }
        Button("Minimize") { addActionToGroup(index: index, action: .minimize) }
        Button("Bring to Front") { addActionToGroup(index: index, action: .bringToFront) }
        Divider()
        Button("Hot Key...") { addActionToGroup(index: index, action: .hotkey(keyCode: -1, modifiers: 0, restoreWindow: false, waitFrontmost: true)) }
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
}

// MARK: - Subviews

struct SpaceConditionRow: View {
    let groupIndex: Int
    @Binding var group: RuleGroup
    let availableSpaces: [SpaceInfo]
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Group \(groupIndex + 1)")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))
            
            Divider().opacity(0.3)
            
            HStack(alignment: .center, spacing: 12) {
                Text("Spaces:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                if availableSpaces.isEmpty {
                    Text("No spaces detected")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(availableSpaces) { space in
                                let isSelected = group.targetSpaceIDs.contains(space.id)
                                Button {
                                    if isSelected {
                                        group.targetSpaceIDs.remove(space.id)
                                    } else {
                                        group.targetSpaceIDs.insert(space.id)
                                    }
                                } label: {
                                    Text(space.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
                                        )
                                        .foregroundColor(isSelected ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct ActionListRows: View {
    @Binding var actions: [ActionItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 0) {
                    Divider().opacity(0.3)
                    ActionRowContent(
                        index: index,
                        item: $actions[index],
                        onDelete: { 
                            withAnimation {
                                _actions.wrappedValue = _actions.wrappedValue.enumerated()
                                    .filter { $0.offset != index }
                                    .map { $0.element }
                            }
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .onMove { indices, newOffset in
                actions.move(fromOffsets: indices, toOffset: newOffset)
            }
        }
    }
}

struct AddActionRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let menuContent: Content
    
    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack {
                Menu {
                    menuContent
                } label: {
                    Label("Add Action", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.accentColor)
                .fixedSize()
                Spacer()
            }
            .padding(8)
        }
    }
}

// MARK: - Action Content

struct ActionRowContent: View {
    let index: Int
    @Binding var item: ActionItem
    let onDelete: () -> Void
    
    @State private var isRecording = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.2))
                
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                
                Group {
                    switch item.value {
                    case .globalHotkey(let code, let mods):
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                ModifierToggle(title: "⌘", flag: .command, current: mods) { toggleModifier(.command, current: mods) }
                                ModifierToggle(title: "⇧", flag: .shift, current: mods) { toggleModifier(.shift, current: mods) }
                                ModifierToggle(title: "⌥", flag: .option, current: mods) { toggleModifier(.option, current: mods) }
                                ModifierToggle(title: "⌃", flag: .control, current: mods) { toggleModifier(.control, current: mods) }
                            }
                            
                            KeyCaptureButton(keyCode: code) { newCode in
                                item.value = .globalHotkey(keyCode: newCode, modifiers: mods)
                            }
                        }
                        
                    case .hotkey(let code, let mods, _, _):
                        HStack(spacing: 8) {
                            Button(action: { isRecording = true }) {
                                if isRecording {
                                    Text("Recording...")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.red)
                                } else {
                                    HStack(spacing: 4) {
                                        Text(code == -1 ? "Shortcut" : ShortcutHelper.format(code: code, modifiers: mods))
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button { withAnimation { isExpanded.toggle() } } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 11))
                                    .foregroundColor(isExpanded ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                    default:
                        Text(item.value.localizedString)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.2))
                }
                .buttonStyle(.plain)
            }
            
            if case .hotkey(let c, let m, let r, let w) = item.value, isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Manual activation", isOn: Binding(
                        get: { w },
                        set: { item.value = .hotkey(keyCode: c, modifiers: m, restoreWindow: $0 ? false : r, waitFrontmost: $0) }
                    ))
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    
                    if !w {
                        Toggle("Restore window", isOn: Binding(
                            get: { r },
                            set: { item.value = .hotkey(keyCode: c, modifiers: m, restoreWindow: $0, waitFrontmost: m == 0 ? false : w) }
                        ))
                        .font(.system(size: 11))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                }
                .padding(.leading, 32)
            }
            
            if isRecording {
                Text("").frame(width: 0, height: 0).onAppear { startRecording(item: item) }
            }
        }
    }
    
    private func toggleModifier(_ flag: NSEvent.ModifierFlags, current: UInt) {
        let raw = flag.rawValue
        let hasIt = (current & raw) != 0
        var newMods = current
        if hasIt { newMods &= ~raw }
        else { newMods |= raw }
        if case .globalHotkey(let c, _) = item.value {
            item.value = .globalHotkey(keyCode: c, modifiers: newMods)
        }
    }
    
    private func startRecording(item: ActionItem) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if isRecording {
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                let code = Int(event.keyCode)
                if case .hotkey(_, _, let r, let w) = item.value {
                    self.item.value = .hotkey(keyCode: code, modifiers: UInt(mods), restoreWindow: r, waitFrontmost: w)
                }
                isRecording = false
                return nil
            }
            return event
        }
    }
}

struct KeyCaptureButton: View {
    let keyCode: Int
    let onUpdate: (Int) -> Void
    @State private var isListening = false
    
    var body: some View {
        Button(action: { isListening = true }) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isListening ? Color.accentColor.opacity(0.05) : Color.primary.opacity(0.04))
                
                if isListening {
                    Text("...")
                        .font(.system(size: 11, weight: .bold))
                } else {
                    Text(displayString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
            .frame(width: 36, height: 20)
        }
        .buttonStyle(.plain)
        .overlay(
            Group {
                if isListening {
                    KeyReceiver { event in
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

struct ModifierToggle: View {
    let title: String
    let flag: NSEvent.ModifierFlags
    let current: UInt
    let action: () -> Void
    var isOn: Bool { (current & flag.rawValue) != 0 }
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .frame(width: 18, height: 18)
            .background(isOn ? Color.accentColor : Color.primary.opacity(0.05))
            .foregroundColor(isOn ? .white : .secondary)
            .cornerRadius(4)
            .onTapGesture(perform: action)
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

import SwiftUI
internal import UniformTypeIdentifiers

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
        VStack(spacing: 0) {
            appSelectorHeader.zIndex(1)
            Divider()
            
            List {
                // Top Spacer
                Section { Color.clear.frame(height: 12) }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                
                // --- GROUPS ---
                ForEach(Array(workingRule.groups.enumerated()), id: \.element.id) { index, group in
                    Section {
                        // 1. Condition
                        SpaceConditionRow(
                            groupIndex: index,
                            group: $workingRule.groups[index],
                            availableSpaces: availableSpaces,
                            onRemove: { withAnimation { _ = workingRule.groups.remove(at: index) } }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        
                        // 2. Actions
                        ActionListRows(actions: $workingRule.groups[index].actions)
                        
                        // 3. Add Button
                        AddActionRow {
                            addActionToGroup(index: index, action: .show)
                        } menuContent: {
                            actionMenu(for: index)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        
                        // Spacer
                        Color.clear.frame(height: 24)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                
                // --- ADD GROUP ---
                Section {
                    Button {
                        withAnimation { workingRule.groups.append(RuleGroup(targetSpaceIDs: [], actions: [])) }
                    } label: {
                        HStack { Image(systemName: "plus.rectangle.on.rectangle"); Text("Add Workflow Group") }
                            .font(.headline).foregroundColor(.blue)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparator(.hidden)
                } footer: {
                    Color.clear.frame(height: 24)
                }
                
                // --- FALLBACK WIDGET (Rebuilt) ---
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack {
                            Image(systemName: "arrow.triangle.branch").foregroundColor(.secondary)
                            Text("Fallback (All Other Spaces)").font(.headline).foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        
                        Divider()
                        
                        // Actions List
                        if workingRule.elseActions.isEmpty {
                            Text("Do Nothing")
                                .italic().foregroundColor(.secondary)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(Array(workingRule.elseActions.enumerated()), id: \.element.id) { i, item in
                                VStack(spacing: 0) {
                                    ActionRowContent(
                                        index: i,
                                        item: $workingRule.elseActions[i],
                                        onDelete: { workingRule.elseActions.remove(at: i) }
                                    )
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    
                                    if i < workingRule.elseActions.count - 1 {
                                        Divider().padding(.leading, 12)
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Add Button (Integrated)
                        HStack {
                            Menu {
                                Button("Show") { workingRule.elseActions.append(ActionItem(.show)) }
                                Button("Hide") { workingRule.elseActions.append(ActionItem(.hide)) }
                                Button("Minimize") { workingRule.elseActions.append(ActionItem(.minimize)) } // ADDED MINIMIZE
                                Divider()
                                Button("Simulate Gloabl Hotkey") { workingRule.elseActions.append(ActionItem(.globalHotkey(keyCode: -1, modifiers: 0))) }
                            } label: {
                                Label("Add Action", systemImage: "plus")
                                    .font(.caption).fontWeight(.medium)
                            }
                            .menuStyle(.borderlessButton)
                            .foregroundColor(.blue)
                            .fixedSize()
                            
                            Spacer()
                        }
                        .padding(12) // Bottom padding for the widget
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15)))
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            footerView
        }
        .frame(width: 800, height: 600)
        .onAppear { loadRunningApps() }
    }
    
    // MARK: - Helpers
    private func addActionToGroup(index: Int, action: WindowAction) {
        workingRule.groups[index].actions.append(ActionItem(action))
    }
    @ViewBuilder private func actionMenu(for index: Int) -> some View {
        Button("Show") { addActionToGroup(index: index, action: .show) }
        Button("Hide") { addActionToGroup(index: index, action: .hide) }
        Button("Minimize") { addActionToGroup(index: index, action: .minimize) }
        Button("Bring to Front") { addActionToGroup(index: index, action: .bringToFront) }
        Divider()
        Button("Simulate App Hotkey...") { addActionToGroup(index: index, action: .hotkey(keyCode: -1, modifiers: 0, restoreWindow: false, waitFrontmost: true)) }
        Button("Simulate Global Hotkey...") { addActionToGroup(index: index, action: .globalHotkey(keyCode: -1, modifiers: 0)) }
    }
    
    // ... (appSelectorHeader, footerView, selectApp, pickOtherApp, loadRunningApps same as previous) ...
    private var appSelectorHeader: some View {
        ZStack(alignment: .leading) {
            Color(NSColor.controlBackgroundColor).ignoresSafeArea()
            Menu {
                if !runningApps.isEmpty {
                    Section("Running Applications") {
                        ForEach(runningApps, id: \.id) { app in
                            Button { selectApp(name: app.name, id: app.id) } label: { HStack { Image(nsImage: app.icon); Text(app.name) } }
                        }
                    }
                }
                Divider()
                Button("Choose other app...") { pickOtherApp() }
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    if !workingRule.appBundleID.isEmpty, let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 48, height: 48)
                    } else {
                        Image(systemName: "app.dashed").resizable().frame(width: 48, height: 48).foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workingRule.appBundleID.isEmpty ? "Select Application" : workingRule.appName).font(.title2).fontWeight(.bold)
                        Text(workingRule.appBundleID.isEmpty ? "Click to choose" : workingRule.appBundleID).font(.caption).foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 72)
    }
    
    private var footerView: some View {
        HStack {
            Button("Cancel", action: onCancel).keyboardShortcut(.escape, modifiers: [])
            Spacer()
            Button("Save Rule") { onSave(workingRule) }
                .buttonStyle(.borderedProminent)
                .disabled(workingRule.appBundleID.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(16).background(Color(NSColor.controlBackgroundColor))
    }
    
    private func selectApp(name: String, id: String) { withAnimation { workingRule.appName = name; workingRule.appBundleID = id } }
    private func pickOtherApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.begin { if $0 == .OK, let url = panel.url {
            let b = Bundle(url: url)
            let id = b?.bundleIdentifier ?? ""
            let name = (b?.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            if !id.isEmpty { DispatchQueue.main.async { self.selectApp(name: name, id: id) } }
        }}
    }
    func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        self.runningApps = apps.map { (name: $0.localizedName ?? "Unknown", id: $0.bundleIdentifier ?? "", icon: $0.icon ?? NSImage()) }.sorted { $0.name < $1.name }
    }
}

// ... (SpaceConditionRow, ActionListRows, AddActionRow same as previous) ...
struct SpaceConditionRow: View {
    let groupIndex: Int; @Binding var group: RuleGroup; let availableSpaces: [SpaceInfo]; let onRemove: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Workflow Group \(groupIndex + 1)").font(.headline); Spacer(); Button(action: onRemove) { Image(systemName: "trash").foregroundColor(.secondary) }.buttonStyle(.plain) }
            .padding(12).background(Color.secondary.opacity(0.05)); Divider()
            HStack(alignment: .top) {
                Text("Active in:").font(.caption).fontWeight(.bold).foregroundColor(.secondary).padding(.top, 4)
                if availableSpaces.isEmpty { Text("No spaces detected").font(.caption).foregroundColor(.secondary).padding(.top, 4) } else {
                    ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(availableSpaces) { space in let isSelected = group.targetSpaceIDs.contains(space.id); Toggle(isOn: Binding(get: { isSelected }, set: { val in if val { group.targetSpaceIDs.insert(space.id) } else { group.targetSpaceIDs.remove(space.id) } })) { Text(space.name).font(.caption).padding(.horizontal, 8).padding(.vertical, 4) }.toggleStyle(.button).buttonStyle(.bordered).tint(isSelected ? .blue : .gray).opacity(isSelected ? 1 : 0.6) } } }
                }
            }.padding(12); Divider()
        }.background(Color(NSColor.controlBackgroundColor)).clipShape(CustomCornerShape(radius: 8, corners: [.topLeft, .topRight])).overlay(CustomCornerShape(radius: 8, corners: [.topLeft, .topRight]).stroke(Color.gray.opacity(0.15))).padding(.horizontal, 20)
    }
}

struct ActionListRows: View {
    @Binding var actions: [ActionItem]
    var body: some View {
        ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
            VStack(spacing: 0) {
                ActionRowContent(index: index, item: $actions[index], onDelete: { actions.remove(at: index) }).padding(.horizontal, 12).padding(.vertical, 8)
                if index < actions.count - 1 { Divider().padding(.leading, 12) }
            }.background(Color(NSColor.controlBackgroundColor)).overlay(Rectangle().strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)).listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)).listRowSeparator(.hidden)
        }.onMove { indices, newOffset in actions.move(fromOffsets: indices, toOffset: newOffset) }
    }
}

struct AddActionRow<Content: View>: View {
    let action: () -> Void; @ViewBuilder let menuContent: Content
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack { Menu { menuContent } label: { Label("Add Action", systemImage: "plus").font(.caption).fontWeight(.medium) }.menuStyle(.borderlessButton).foregroundColor(.blue).fixedSize(); Spacer() }.padding(10)
        }.background(Color(NSColor.controlBackgroundColor)).clipShape(CustomCornerShape(radius: 8, corners: [.bottomLeft, .bottomRight])).overlay(CustomCornerShape(radius: 8, corners: [.bottomLeft, .bottomRight]).stroke(Color.gray.opacity(0.15))).padding(.horizontal, 20)
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
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary.opacity(0.2)).font(.caption)
                Text("\(index + 1).").font(.caption).monospacedDigit().foregroundColor(.secondary).frame(width: 20, alignment: .trailing)
                
                switch item.value {
                    
                // --- GLOBAL KEY (Updated with KeyCaptureView) ---
                case .globalHotkey(let code, let mods):
                    HStack(spacing: 12) {
                        Text("Global Key:").font(.subheadline).foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            ModifierToggle("⌘", flag: .command, current: mods) { toggleModifier(.command, current: mods) }
                            ModifierToggle("⇧", flag: .shift, current: mods) { toggleModifier(.shift, current: mods) }
                            ModifierToggle("⌥", flag: .option, current: mods) { toggleModifier(.option, current: mods) }
                            ModifierToggle("⌃", flag: .control, current: mods) { toggleModifier(.control, current: mods) }
                        }
                        
                        // FIX: Replaced TextField with KeyCaptureButton
                        KeyCaptureButton(keyCode: code) { newCode in
                            item.value = .globalHotkey(keyCode: newCode, modifiers: mods)
                        }
                    }
                    
                case .hotkey(let code, let mods, _, _):
                    Button(action: { isRecording = true }) {
                        if isRecording {
                            Text("Recording...").foregroundColor(.red).fontWeight(.bold)
                        } else {
                            HStack {
                                Image(systemName: "keyboard")
                                Text(code == -1 ? "Click to Record" : ShortcutHelper.format(code: code, modifiers: mods))
                            }
                            .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(4).background(Color.gray.opacity(0.1)).cornerRadius(4)
                    
                    Button { withAnimation { isExpanded.toggle() } } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.caption)
                            .foregroundColor(isExpanded ? .blue : .secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                default:
                    Text(item.value.localizedString).font(.subheadline)
                }
                
                Spacer()
                Button(action: onDelete) { Image(systemName: "xmark").font(.caption2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }
            
            // Expanded Settings for Standard Hotkey
            if case .hotkey(let c, let m, let r, let w) = item.value, isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Toggle("Wait for Manual Activation", isOn: Binding(
                        get: { w },
                        set: { item.value = .hotkey(keyCode: c, modifiers: m, restoreWindow: $0 ? false : r, waitFrontmost: $0) }
                    ))
                    .toggleStyle(.switch).controlSize(.mini)
                    
                    if !w {
                        Toggle("Restore Previously Active Window", isOn: Binding(
                            get: { r },
                            set: { item.value = .hotkey(keyCode: c, modifiers: m, restoreWindow: $0, waitFrontmost: w) }
                        ))
                        .toggleStyle(.switch).controlSize(.mini)
                    } else {
                        Text("App will wait until you manually switch to it.").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 36).padding(.bottom, 4)
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

// FIX: Custom Button to capture single key stroke immediately
struct KeyCaptureButton: View {
    let keyCode: Int
    let onUpdate: (Int) -> Void
    @State private var isListening = false
    
    var body: some View {
        Button(action: { isListening = true }) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isListening ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                    .background(Color(NSColor.controlBackgroundColor))
                
                if isListening {
                    Text("Type").font(.caption).foregroundColor(.blue)
                } else {
                    Text(displayString)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 40, height: 24)
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

// Hidden view to capture one key event
struct KeyReceiver: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: KeyView, context: Context) {
        // Force focus so we catch the key
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

// UI Helper for Modifier Toggles
struct ModifierToggle: View {
    let title: String
    let flag: NSEvent.ModifierFlags
    let current: UInt
    let action: () -> Void
    var isOn: Bool { (current & flag.rawValue) != 0 }
    init(_ title: String, flag: NSEvent.ModifierFlags, current: UInt, action: @escaping () -> Void) {
        self.title = title; self.flag = flag; self.current = current; self.action = action
    }
    var body: some View {
        Text(title).font(.system(size: 11, weight: .bold)).frame(width: 20, height: 20).background(isOn ? Color.blue : Color.gray.opacity(0.2)).foregroundColor(isOn ? .white : .secondary).cornerRadius(4).onTapGesture(perform: action)
    }
}

// Shape Helper (Same)
struct CustomCornerShape: Shape {
    var radius: CGFloat; var corners: RectCorner
    struct RectCorner: OptionSet {
        let rawValue: Int
        static let topLeft = RectCorner(rawValue: 1 << 0); static let topRight = RectCorner(rawValue: 1 << 1); static let bottomLeft = RectCorner(rawValue: 1 << 2); static let bottomRight = RectCorner(rawValue: 1 << 3)
        static let all: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(); let p1 = CGPoint(x: rect.minX, y: corners.contains(.topLeft) ? rect.minY + radius : rect.minY); let p2 = CGPoint(x: corners.contains(.topLeft) ? rect.minX + radius : rect.minX, y: rect.minY); let p3 = CGPoint(x: corners.contains(.topRight) ? rect.maxX - radius : rect.maxX, y: rect.minY); let p4 = CGPoint(x: rect.maxX, y: corners.contains(.topRight) ? rect.minY + radius : rect.minY); let p5 = CGPoint(x: rect.maxX, y: corners.contains(.bottomRight) ? rect.maxY - radius : rect.maxY); let p6 = CGPoint(x: corners.contains(.bottomRight) ? rect.maxX - radius : rect.maxX, y: rect.maxY); let p7 = CGPoint(x: corners.contains(.bottomLeft) ? rect.minX + radius : rect.minX, y: rect.maxY); let p8 = CGPoint(x: rect.minX, y: corners.contains(.bottomLeft) ? rect.maxY - radius : rect.maxY)
        path.move(to: p1); path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: p2, radius: radius); path.addLine(to: p3); path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: p4, radius: radius); path.addLine(to: p5); path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: p6, radius: radius); path.addLine(to: p7); path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: p8, radius: radius); path.closeSubpath(); return path
    }
}

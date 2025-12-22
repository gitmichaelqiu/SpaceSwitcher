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
        VStack(spacing: 0) {
            appSelectorHeader.zIndex(1)
            Divider()
            
            // Main Scrollable Area
            ScrollView {
                scrollContent
                    .padding(20)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            footerView
        }
        .frame(width: 800, height: 600)
        .onAppear { loadRunningApps() }
    }
    
    // MARK: - Extracted Scroll Content
    @ViewBuilder
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            
            // 1. Groups
            ForEach(Array(workingRule.groups.enumerated()), id: \.element.id) { index, group in
                GroupEditorCard(
                    groupIndex: index,
                    group: $workingRule.groups[index],
                    allGroups: workingRule.groups,
                    availableSpaces: availableSpaces,
                    onRemove: {
                        withAnimation {
                            _ = workingRule.groups.remove(at: index)
                        }
                    }
                )
            }
            
            // 2. Add Group Button
            Button {
                withAnimation {
                    // Default to empty actions
                    workingRule.groups.append(RuleGroup(targetSpaceIDs: [], actions: []))
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Space Group")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundColor(.blue.opacity(0.5))
                )
            }
            .buttonStyle(.plain)
            
            Divider()
            
            // 3. Else / Fallback
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "asterisk.circle.fill")
                        .foregroundColor(.secondary)
                    Text("In All Other Spaces")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.bottom, 12)
                
                ActionSequenceEditor(
                    actions: $workingRule.elseActions,
                    placeholder: "Do Nothing"
                )
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1)))
        }
    }
    
    // MARK: - Subviews
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
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
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

// MARK: - Group Card Editor
struct GroupEditorCard: View {
    let groupIndex: Int
    @Binding var group: RuleGroup
    let allGroups: [RuleGroup]
    let availableSpaces: [SpaceInfo]
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workflow Group \(groupIndex + 1)").font(.headline).foregroundColor(.primary)
                Spacer()
                Button(action: onRemove) { Image(systemName: "trash").foregroundColor(.red.opacity(0.8)) }.buttonStyle(.plain)
            }
            .padding(12).background(Color.secondary.opacity(0.05))
            
            HStack(alignment: .top, spacing: 0) {
                // Spaces
                VStack(alignment: .leading, spacing: 8) {
                    Text("If in Spaces:").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if availableSpaces.isEmpty { Text("No spaces").font(.caption).foregroundColor(.secondary) }
                            ForEach(availableSpaces) { space in
                                let isUsedElsewhere = isSpaceUsedElsewhere(space.id)
                                let isSelectedHere = group.targetSpaceIDs.contains(space.id)
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { isSelectedHere },
                                        set: { val in if val { group.targetSpaceIDs.insert(space.id) } else { group.targetSpaceIDs.remove(space.id) } }
                                    )) {
                                        Text("\(space.number). \(space.name)").font(.body).lineLimit(1)
                                            .foregroundColor(isUsedElsewhere && !isSelectedHere ? .secondary.opacity(0.5) : .primary)
                                    }
                                    .toggleStyle(.checkbox).disabled(isUsedElsewhere && !isSelectedHere)
                                    Spacer()
                                    if isUsedElsewhere && !isSelectedHere { Text("(Used)").font(.caption2).foregroundColor(.secondary) }
                                }
                            }
                        }
                    }
                    .frame(height: 120)
                }
                .padding(12).frame(width: 250)
                
                Divider()
                
                // Actions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Do Actions:").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    ActionSequenceEditor(actions: $group.actions, placeholder: "No actions defined")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
    }
    
    private func isSpaceUsedElsewhere(_ spaceID: String) -> Bool {
        for (idx, g) in allGroups.enumerated() {
            if idx != groupIndex && g.targetSpaceIDs.contains(spaceID) { return true }
        }
        return false
    }
}

// MARK: - Action Sequence Editor
struct ActionSequenceEditor: View {
    @Binding var actions: [WindowAction]
    var placeholder: String
    @State private var recordingIndex: Int? = nil
    @State private var draggedItem: WindowAction?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if actions.isEmpty {
                Text(placeholder)
                    .font(.caption)
                    .italic()
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                    ActionRowView(
                        index: index,
                        action: action,
                        actions: $actions,
                        draggedItem: $draggedItem,
                        isRecording: recordingIndex == index,
                        onRecord: { startRecording(at: index) },
                        onDelete: { actions.remove(at: index) }
                    )
                }
            }
            
            Menu {
                Button("Show") { actions.append(.show) }
                Button("Bring to Front") { actions.append(.bringToFront) }
                Button("Hide") { actions.append(.hide) }
                Button("Minimize") { actions.append(.minimize) }
                Divider()
                Button("Simulate Hotkey...") { actions.append(.hotkey(keyCode: -1, modifiers: 0)) }
            } label: { HStack { Image(systemName: "plus"); Text("Add Action") }.font(.caption).fontWeight(.medium) }
            .menuStyle(.borderlessButton).foregroundColor(.blue).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.default, value: actions)
    }
    
    private func startRecording(at index: Int) {
        recordingIndex = index
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.recordingIndex == index {
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                let code = Int(event.keyCode)
                self.actions[index] = .hotkey(keyCode: code, modifiers: UInt(mods))
                self.recordingIndex = nil
                return nil
            }
            return event
        }
    }
}

// MARK: - Action Row View
struct ActionRowView: View {
    let index: Int
    let action: WindowAction
    @Binding var actions: [WindowAction]
    @Binding var draggedItem: WindowAction?
    let isRecording: Bool
    let onRecord: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            // Drag Handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("\(index + 1).").font(.caption).monospacedDigit().foregroundColor(.secondary).frame(width: 20, alignment: .trailing)
            
            if case .hotkey(let code, let mods) = action {
                Button(action: onRecord) {
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
                .buttonStyle(.plain).padding(.horizontal, 4).padding(.vertical, 2)
                .background(isRecording ? Color.red.opacity(0.1) : Color.clear).cornerRadius(4)
            } else {
                Text(action.localizedString).font(.subheadline)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain).foregroundColor(.secondary)
        }
        .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        // UPDATED: Hide the original row while it is being draggedf
        .opacity(draggedItem == action ? 0.0 : 1.0)
        // Drag and Drop Logic
        .onDrag {
            self.draggedItem = action
            return NSItemProvider(object: action.id as NSString)
        }
        .onDrop(of: [.text], delegate: ActionDropDelegate(item: action, items: $actions, draggedItem: $draggedItem))
    }
}

// MARK: - Drop Delegate for Reordering
struct ActionDropDelegate: DropDelegate {
    let item: WindowAction
    @Binding var items: [WindowAction]
    @Binding var draggedItem: WindowAction?
    
    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        
        if draggedItem != item {
            if let from = items.firstIndex(of: draggedItem),
               let to = items.firstIndex(of: item) {
                withAnimation {
                    items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
}

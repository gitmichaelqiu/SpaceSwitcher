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
            // 1. App Header
            appSelectorHeader
                .zIndex(1)
            
            Divider()
            
            // 2. Main List with Native Reordering
            List {
                // GROUPS
                ForEach(Array(workingRule.groups.enumerated()), id: \.element.id) { index, group in
                    Section {
                        // Actions List for this group
                        ActionListSection(actions: $workingRule.groups[index].actions)
                    } header: {
                        GroupHeaderView(
                            groupIndex: index,
                            group: $workingRule.groups[index],
                            allGroups: workingRule.groups,
                            availableSpaces: availableSpaces,
                            onRemove: { withAnimation { _ = workingRule.groups.remove(at: index) } }
                        )
                        .padding(.bottom, 8)
                    }
                }
                
                // ADD GROUP BUTTON
                Section {
                    Button {
                        withAnimation {
                            workingRule.groups.append(RuleGroup(targetSpaceIDs: [], actions: []))
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Space Group")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                
                // ELSE / FALLBACK
                Section {
                    ActionListSection(actions: $workingRule.elseActions)
                } header: {
                    HStack {
                        Image(systemName: "asterisk.circle.fill").foregroundColor(.secondary)
                        Text("In All Other Spaces").font(.headline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.sidebar) // Clean look on macOS
            
            Divider()
            
            // 3. Footer
            footerView
        }
        .frame(width: 800, height: 600)
        .onAppear { loadRunningApps() }
    }
    
    // MARK: - Components
    
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

// MARK: - Header View (Spaces Selector)
struct GroupHeaderView: View {
    let groupIndex: Int
    @Binding var group: RuleGroup
    let allGroups: [RuleGroup]
    let availableSpaces: [SpaceInfo]
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workflow Group \(groupIndex + 1)")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Active in Spaces:").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                
                if availableSpaces.isEmpty {
                    Text("No spaces detected").font(.caption).foregroundColor(.secondary)
                } else {
                    // Custom grid/flow layout for spaces
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading) {
                        ForEach(availableSpaces) { space in
                            let isUsedElsewhere = isSpaceUsedElsewhere(space.id)
                            let isSelectedHere = group.targetSpaceIDs.contains(space.id)
                            
                            Toggle(isOn: Binding(
                                get: { isSelectedHere },
                                set: { val in if val { group.targetSpaceIDs.insert(space.id) } else { group.targetSpaceIDs.remove(space.id) } }
                            )) {
                                Text("\(space.number). \(space.name)")
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .foregroundColor(isUsedElsewhere && !isSelectedHere ? .secondary.opacity(0.5) : .primary)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(isUsedElsewhere && !isSelectedHere)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15)))
    }
    
    private func isSpaceUsedElsewhere(_ spaceID: String) -> Bool {
        for (idx, g) in allGroups.enumerated() {
            if idx != groupIndex && g.targetSpaceIDs.contains(spaceID) { return true }
        }
        return false
    }
}

// MARK: - Action List Section (Reorderable)
struct ActionListSection: View {
    @Binding var actions: [ActionItem]
    @State private var recordingIndex: Int? = nil
    
    var body: some View {
        if actions.isEmpty {
            Text("Do Nothing")
                .font(.caption).italic().foregroundColor(.secondary)
                .listRowBackground(Color.clear)
        }
        
        ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
            ActionRowContent(
                index: index,
                item: item,
                isRecording: recordingIndex == index,
                onRecord: { startRecording(at: index) },
                onDelete: { actions.remove(at: index) }
            )
        }
        .onMove { indices, newOffset in
            actions.move(fromOffsets: indices, toOffset: newOffset)
        }
        
        // Add Button Row
        HStack {
            Menu {
                Button("Show") { actions.append(ActionItem(.show)) }
                Button("Bring to Front") { actions.append(ActionItem(.bringToFront)) }
                Button("Hide") { actions.append(ActionItem(.hide)) }
                Button("Minimize") { actions.append(ActionItem(.minimize)) }
                Divider()
                Button("Simulate Hotkey...") { actions.append(ActionItem(.hotkey(keyCode: -1, modifiers: 0))) }
            } label: {
                Label("Add Action", systemImage: "plus")
                    .font(.caption).fontWeight(.medium)
            }
            .menuStyle(.borderlessButton)
            .foregroundColor(.blue)
            
            Spacer()
        }
        .padding(.top, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    
    private func startRecording(at index: Int) {
        recordingIndex = index
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.recordingIndex == index {
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                let code = Int(event.keyCode)
                self.actions[index].value = .hotkey(keyCode: code, modifiers: UInt(mods))
                self.recordingIndex = nil
                return nil
            }
            return event
        }
    }
}

struct ActionRowContent: View {
    let index: Int
    let item: ActionItem
    let isRecording: Bool
    let onRecord: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Text("\(index + 1).").font(.caption).monospacedDigit().foregroundColor(.secondary).frame(width: 20, alignment: .trailing)
            
            if case .hotkey(let code, let mods) = item.value {
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
                Text(item.value.localizedString).font(.subheadline)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

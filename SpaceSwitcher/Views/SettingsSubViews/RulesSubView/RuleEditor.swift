import SwiftUI
import UniformTypeIdentifiers

struct RuleEditor: View {
    @State private var workingRule: AppRule
    let availableSpaces: [SpaceInfo]
    let onSave: (AppRule) -> Void
    let onCancel: () -> Void
    
    // Running Apps List
    @State private var runningApps: [(name: String, id: String, icon: NSImage)] = []
    
    init(rule: AppRule, availableSpaces: [SpaceInfo], onSave: @escaping (AppRule) -> Void, onCancel: @escaping () -> Void) {
        self._workingRule = State<AppRule>(initialValue: rule)
        self.availableSpaces = availableSpaces
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            appSelectorHeader.zIndex(1)
            Divider()
            
            HStack(alignment: .top, spacing: 16) {
                spacesColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                actionsColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            footerView
        }
        .frame(width: 750, height: 550) // Slightly wider for workflows
        .onAppear { loadRunningApps() }
    }
    
    // MARK: - 1. App Selector Header
    private var appSelectorHeader: some View {
        ZStack(alignment: .leading) {
            Color(NSColor.controlBackgroundColor).ignoresSafeArea()
            Menu {
                if !runningApps.isEmpty {
                    Section("Running Applications") {
                        ForEach(runningApps, id: \.id) { app in
                            Button { selectApp(name: app.name, id: app.id) } label: {
                                HStack { Image(nsImage: app.icon); Text(app.name) }
                            }
                        }
                    }
                }
                Divider()
                Button("Choose other app...") { pickOtherApp() }
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    if !workingRule.appBundleID.isEmpty,
                       let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable().frame(width: 48, height: 48).shadow(radius: 1)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable().frame(width: 48, height: 48).foregroundColor(.secondary.opacity(0.5))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(workingRule.appBundleID.isEmpty ? "Select Application" : workingRule.appName)
                                .font(.title2).fontWeight(.bold).foregroundColor(.primary)
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.subheadline).foregroundColor(.secondary.opacity(0.5))
                        }
                        Text(workingRule.appBundleID.isEmpty ? "Click here to choose target" : workingRule.appBundleID)
                            .font(.caption).foregroundColor(.secondary).monospaced().lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 72)
    }
    
    // MARK: - 2. Left Column: Spaces
    private var spacesColumn: some View {
        GroupBox(label: Label("Target Spaces", systemImage: "macwindow")) {
            VStack(alignment: .leading, spacing: 0) {
                if availableSpaces.isEmpty {
                    VStack {
                        Spacer()
                        Text("No spaces detected.").foregroundColor(.secondary)
                        Text("Is DesktopRenamer running?").font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(availableSpaces) { space in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { workingRule.targetSpaceIDs.contains(space.id) },
                                    set: { isSelected in
                                        if isSelected { workingRule.targetSpaceIDs.insert(space.id) }
                                        else { workingRule.targetSpaceIDs.remove(space.id) }
                                    }
                                )) {
                                    HStack {
                                        Text("\(space.number)")
                                            .font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
                                            .frame(width: 25, alignment: .trailing)
                                        Text(space.name).font(.body).fontWeight(.medium).lineLimit(1)
                                        Spacer()
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - 3. Right Column: Actions
    private var actionsColumn: some View {
        GroupBox(label: Label("Window Actions", systemImage: "slider.horizontal.3")) {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Sequence A: Match
                    ActionSequenceEditor(
                        title: "In Target Spaces",
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        actions: $workingRule.matchActions
                    )
                    
                    Divider()
                    
                    // Sequence B: Else
                    ActionSequenceEditor(
                        title: "In Other Spaces",
                        icon: "xmark.circle.fill",
                        iconColor: .red,
                        actions: $workingRule.elseActions
                    )
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
        }
    }
    
    // MARK: - 4. Footer
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
    
    // MARK: - Helpers
    private func selectApp(name: String, id: String) {
        withAnimation { workingRule.appName = name; workingRule.appBundleID = id }
    }
    private func pickOtherApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = "Select an application to control"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let bundle = Bundle(url: url)
                let id = bundle?.bundleIdentifier ?? ""
                var name = bundle?.infoDictionary?["CFBundleName"] as? String
                if name == nil { name = url.deletingPathExtension().lastPathComponent }
                if !id.isEmpty { DispatchQueue.main.async { self.selectApp(name: name ?? "Unknown", id: id) } }
            }
        }
    }
    func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        self.runningApps = apps.map { (name: $0.localizedName ?? "Unknown", id: $0.bundleIdentifier ?? "", icon: $0.icon ?? NSImage()) }.sorted { $0.name < $1.name }
    }
}

// MARK: - Action Sequence Editor Helper
struct ActionSequenceEditor: View {
    let title: String
    let icon: String
    let iconColor: Color
    @Binding var actions: [WindowAction]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(iconColor)
                Text(title).font(.headline)
            }
            
            if actions.isEmpty {
                Text("No actions (Do Nothing)")
                    .font(.caption).italic().foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption).monospacedDigit().foregroundColor(.secondary)
                        Text(action.localizedString)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        // Remove Button
                        Button {
                            actions.remove(at: index)
                        } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                    
                    if index < actions.count - 1 {
                        Image(systemName: "arrow.down")
                            .font(.caption2).foregroundColor(.secondary.opacity(0.5))
                            .padding(.leading, 12)
                    }
                }
            }
            
            // Add Action Menu
            Menu {
                ForEach(WindowAction.allCases) { action in
                    Button(action.localizedString) {
                        actions.append(action)
                    }
                }
            } label: {
                Label("Add Step", systemImage: "plus")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .padding(.top, 4)
            .foregroundColor(.blue)
        }
    }
}

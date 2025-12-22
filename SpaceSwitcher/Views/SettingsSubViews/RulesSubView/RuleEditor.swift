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
            // 1. Header (App Selector)
            appSelectorHeader
                .zIndex(1)
            
            Divider()
            
            // 2. Main Content (Two Equal Columns)
            HStack(alignment: .top, spacing: 16) {
                // LEFT: Spaces
                spacesColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // RIGHT: Actions
                actionsColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 3. Footer
            footerView
        }
        .frame(width: 700, height: 500)
        .onAppear {
            loadRunningApps()
        }
    }
    
    // MARK: - 1. App Selector Header
    
    private var appSelectorHeader: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)
                .ignoresSafeArea()
            
            Menu {
                if !runningApps.isEmpty {
                    Section("Running Applications") {
                        ForEach(runningApps, id: \.id) { app in
                            Button {
                                selectApp(name: app.name, id: app.id)
                            } label: {
                                HStack {
                                    Image(nsImage: app.icon)
                                    Text(app.name)
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                Button("Choose other app...") {
                    pickOtherApp()
                }
                
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    // App Icon
                    if !workingRule.appBundleID.isEmpty,
                       let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 48, height: 48) // Optimized size
                            .shadow(radius: 1)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    
                    // App Name & Bundle ID
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(workingRule.appBundleID.isEmpty ? "Select Application" : workingRule.appName)
                                .font(.title2) // Optimized font size
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        
                        Text(workingRule.appBundleID.isEmpty ? "Click here to choose target" : workingRule.appBundleID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Spacer() // Forces alignment to the left
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(height: 90)
    }
    
    // MARK: - 2. Left Column: Spaces
    
    private var spacesColumn: some View {
        GroupBox(label: Label("Target Spaces", systemImage: "macwindow")) {
            VStack(alignment: .leading, spacing: 0) {
                if availableSpaces.isEmpty {
                    VStack {
                        Spacer()
                        Text("No spaces detected.")
                            .foregroundColor(.secondary)
                        Text("Is DesktopRenamer running?")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 25, alignment: .trailing)
                                        
                                        Text(space.name)
                                            .font(.body) // Standard body size
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - 3. Right Column: Actions
    
    private var actionsColumn: some View {
        GroupBox(label: Label("Window Actions", systemImage: "slider.horizontal.3")) {
            VStack {
                Spacer() // Pushes content to vertical center
                
                VStack(alignment: .leading, spacing: 24) { // Increased spacing between blocks
                    
                    // Block A: Match Action
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("In Target Spaces")
                                .font(.headline)
                        }
                        
                        Picker("", selection: $workingRule.matchAction) {
                            ForEach(WindowAction.allCases) { action in
                                Text(action.localizedString).tag(action)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading) // Align picker left
                        
                        Text("Standard behavior: Show")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Block B: Else Action
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("In Other Spaces")
                                .font(.headline)
                        }
                        
                        Picker("", selection: $workingRule.elseAction) {
                            ForEach(WindowAction.allCases) { action in
                                Text(action.localizedString).tag(action)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading) // Align picker left
                        
                        Text("Standard behavior: Hide or Minimize")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                
                Spacer() // Pushes content to vertical center
            }
        }
    }
    
    // MARK: - 4. Footer
    
    private var footerView: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
            
            Spacer()
            
            Button("Save Rule") {
                onSave(workingRule)
            }
            .buttonStyle(.borderedProminent)
            .disabled(workingRule.appBundleID.isEmpty)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Logic Helpers
    
    private func selectApp(name: String, id: String) {
        withAnimation {
            workingRule.appName = name
            workingRule.appBundleID = id
        }
    }
    
    private func pickOtherApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Select an application to control"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let bundle = Bundle(url: url)
                let id = bundle?.bundleIdentifier ?? ""
                
                var name = bundle?.infoDictionary?["CFBundleName"] as? String
                if name == nil {
                     name = url.deletingPathExtension().lastPathComponent
                }
                
                if !id.isEmpty {
                    DispatchQueue.main.async {
                        self.selectApp(name: name ?? "Unknown", id: id)
                    }
                }
            }
        }
    }
    
    func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        
        self.runningApps = apps.map { app in
            (name: app.localizedName ?? "Unknown",
             id: app.bundleIdentifier ?? "",
             icon: app.icon ?? NSImage())
        }.sorted { $0.name < $1.name }
    }
}

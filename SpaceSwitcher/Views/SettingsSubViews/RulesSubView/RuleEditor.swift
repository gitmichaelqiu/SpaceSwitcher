import SwiftUI

struct RuleEditor: View {
    @State private var workingRule: AppRule
    let availableSpaces: [SpaceInfo]
    let onSave: (AppRule) -> Void
    let onCancel: () -> Void
    
    // Running Apps List
    @State private var runningApps: [(name: String, id: String, icon: NSImage)] = []
    
    init(rule: AppRule, availableSpaces: [SpaceInfo], onSave: @escaping (AppRule) -> Void, onCancel: @escaping () -> Void) {
        // Explicitly specifying the generic type <AppRule> helps the compiler
        self._workingRule = State<AppRule>(initialValue: rule)
        self.availableSpaces = availableSpaces
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    applicationSection
                    
                    if !workingRule.appBundleID.isEmpty {
                        spacesAndActionsSection
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            footerView
        }
        .frame(width: 650, height: 550)
        .onAppear {
            loadRunningApps()
        }
    }
    
    // MARK: - Sub-Views (Broken down to fix compiler timeout)
    
    private var headerView: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)
                .ignoresSafeArea()
            
            HStack(spacing: 16) {
                // App Icon
                if !workingRule.appBundleID.isEmpty,
                   let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(workingRule.appName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if !workingRule.appBundleID.isEmpty {
                        Text(workingRule.appBundleID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    } else {
                        Text("No application selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(20)
        }
        .frame(height: 90)
    }
    
    private var applicationSection: some View {
        GroupBox(label: Label("Application", systemImage: "app")) {
            if #available(macOS 14.0, *) {
                Menu {
                    ForEach(runningApps, id: \.id) { app in
                        Button {
                            workingRule.appBundleID = app.id
                            workingRule.appName = app.name
                        } label: {
                            HStack {
                                Image(nsImage: app.icon)
                                Text(app.name)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(workingRule.appBundleID.isEmpty ? "Select a running application..." : "Change Application")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.textBackgroundColor))
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.top, 4)
            } else {
                // Fallback on earlier versions
            }
        }
    }
    
    private var spacesAndActionsSection: some View {
        HStack(alignment: .top, spacing: 20) {
            
            // Spaces Column
            GroupBox(label: Label("Active Spaces", systemImage: "macwindow")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select the spaces where this app should be visible.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    if availableSpaces.isEmpty {
                        Text("No spaces detected via DesktopRenamer.")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(availableSpaces) { space in
                                    Toggle(isOn: Binding(
                                        get: { workingRule.targetSpaceIDs.contains(space.id) },
                                        set: { isSelected in
                                            if isSelected { workingRule.targetSpaceIDs.insert(space.id) }
                                            else { workingRule.targetSpaceIDs.remove(space.id) }
                                        }
                                    )) {
                                        HStack {
                                            Text("\(space.number).")
                                                .foregroundColor(.secondary)
                                                .monospacedDigit()
                                                .frame(width: 20, alignment: .trailing)
                                            Text(space.name)
                                                .fontWeight(.medium)
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                        .frame(height: 180)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15)))
                    }
                }
                .padding(8)
            }
            
            // Behavior Column
            VStack(spacing: 20) {
                GroupBox(label: Label("In Target Spaces", systemImage: "checkmark.circle.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $workingRule.matchAction) {
                            ForEach(WindowAction.allCases) { action in
                                Text(action.localizedString).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        
                        Text("Usually 'Show'")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                
                GroupBox(label: Label("In Other Spaces", systemImage: "xmark.circle.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $workingRule.elseAction) {
                            ForEach(WindowAction.allCases) { action in
                                Text(action.localizedString).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        
                        Text("Usually 'Hide' or 'Minimize'")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                
                Spacer()
            }
            .frame(maxWidth: 220)
        }
    }
    
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
        .background(Color(NSColor.windowBackgroundColor))
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

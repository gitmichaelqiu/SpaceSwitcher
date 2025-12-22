import SwiftUI

struct RuleEditor: View {
    @State private var workingRule: AppRule
    let availableSpaces: [SpaceInfo]
    let onSave: (AppRule) -> Void
    let onCancel: () -> Void
    
    // Running Apps List
    @State private var runningApps: [(name: String, id: String, icon: NSImage)] = []
    
    init(rule: AppRule, availableSpaces: [SpaceInfo], onSave: @escaping (AppRule) -> Void, onCancel: @escaping () -> Void) {
        // Explicitly initialize State to satisfy compiler complexity limits
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
    
    // MARK: - Sub-Views
    
    private var headerView: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)
                .ignoresSafeArea()
            
            HStack(spacing: 16) {
                // Large Icon Display
                if !workingRule.appBundleID.isEmpty,
                   let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "gearshape.circle.fill") // Generic rule icon until app selected
                        .resizable()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(workingRule.appBundleID.isEmpty ? "New Rule" : workingRule.appName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if !workingRule.appBundleID.isEmpty {
                        Text("Bundle ID: \(workingRule.appBundleID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    } else {
                        Text("Configure a new switching rule")
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
        GroupBox(label: Label("Target Application", systemImage: "app.dashed")) {
            if #available(macOS 14.0, *) {
                Menu {
                    // Section 1: Dynamic List of Running Apps
                    Section("Running Applications") {
                        ForEach(runningApps, id: \.id) { app in
                            Button {
                                withAnimation(.snappy) {
                                    workingRule.appBundleID = app.id
                                    workingRule.appName = app.name
                                }
                            } label: {
                                HStack {
                                    Image(nsImage: app.icon)
                                    Text(app.name)
                                }
                            }
                        }
                    }
                } label: {
                    // DYNAMIC LABEL: Shows exactly what is selected inside the clickable area
                    HStack {
                        if !workingRule.appBundleID.isEmpty {
                            // 1. Selected State
                            if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                    .resizable()
                                    .frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "app")
                            }
                            
                            Text(workingRule.appName)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("Change")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            // 2. Empty State
                            Text("Select an application...")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
                .menuStyle(.borderlessButton) // Looks like a standard form picker
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
            
            // LEFT COLUMN: Spaces
            GroupBox(label: Label("Active Spaces", systemImage: "macwindow")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Check the spaces where this app belongs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    if availableSpaces.isEmpty {
                        Text("No spaces detected.")
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
                                            Text("\(space.number)")
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .frame(width: 20, alignment: .trailing)
                                            
                                            Text(space.name)
                                                .fontWeight(.medium)
                                            
                                            Spacer()
                                            
                                            if workingRule.targetSpaceIDs.contains(space.id) {
                                                Image(systemName: "checkmark")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
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
            
            // RIGHT COLUMN: Behavior
            VStack(spacing: 20) {
                GroupBox(label: Label("Match Action", systemImage: "checkmark.circle.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $workingRule.matchAction) {
                            ForEach(WindowAction.allCases) { action in
                                Text(action.localizedString).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        
                        Text("When in selected spaces")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                
                GroupBox(label: Label("Else Action", systemImage: "xmark.circle.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $workingRule.elseAction) {
                            ForEach(WindowAction.allCases) { action in
                                Text(action.localizedString).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        
                        Text("When in other spaces")
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

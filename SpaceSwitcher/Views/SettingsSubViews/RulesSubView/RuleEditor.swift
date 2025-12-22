import SwiftUI

struct RuleEditor: View {
    @State private var workingRule: AppRule
    let availableSpaces: [SpaceInfo]
    let onSave: (AppRule) -> Void
    let onCancel: () -> Void
    
    @State private var runningApps: [(name: String, id: String, icon: NSImage)] = []
    
    init(rule: AppRule?, availableSpaces: [SpaceInfo], onSave: @escaping (AppRule) -> Void, onCancel: @escaping () -> Void) {
        _workingRule = State(initialValue: rule ?? AppRule(
            appBundleID: "",
            appName: NSLocalizedString("Select Target App", comment: ""),
            targetSpaceIDs: [],
            matchAction: .show,
            elseAction: .hide
        ))
        self.availableSpaces = availableSpaces
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack {
                Text(workingRule.appBundleID.isEmpty ? "New Rule" : "Edit Rule")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // SECTION 1: TARGET APP
                    appSelectionSection
                    
                    if !workingRule.appBundleID.isEmpty {
                        Divider()
                        
                        HStack(alignment: .top, spacing: 24) {
                            // SECTION 2: SPACE SELECTION (Left Column)
                            spaceSelectionSection
                                .frame(maxWidth: .infinity)
                            
                            // SECTION 3: ACTIONS (Right Column)
                            actionConfigurationSection
                                .frame(maxWidth: 200)
                        }
                    } else {
                        Text("Please select an application to continue.")
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // MARK: - Footer
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
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
        .onAppear {
            loadRunningApps()
        }
    }
    
    // MARK: - Subviews
    
    private var appSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Target Application")
                .font(.headline)
                .foregroundColor(.secondary)
            
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
                HStack(spacing: 12) {
                    if !workingRule.appBundleID.isEmpty,
                       let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workingRule.appName)
                            .fontWeight(.medium)
                        if !workingRule.appBundleID.isEmpty {
                            Text(workingRule.appBundleID)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(4)
            }
            .menuStyle(.borderedButton)
            .frame(maxWidth: 300)
        }
    }
    
    private var spaceSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Target Spaces")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 0) {
                if availableSpaces.isEmpty {
                    Text("No spaces detected.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List {
                        ForEach(availableSpaces) { space in
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { workingRule.targetSpaceIDs.contains(space.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            workingRule.targetSpaceIDs.insert(space.id)
                                        } else {
                                            workingRule.targetSpaceIDs.remove(space.id)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                
                                Text("\(space.number). \(space.name)")
                                    .padding(.leading, 4)
                                
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(height: 180)
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                }
            }
            
            Text("Select the spaces where this app belongs.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var actionConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            
            // Match Action
            VStack(alignment: .leading, spacing: 8) {
                Text("When in Target Space:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                
                Picker("", selection: $workingRule.matchAction) {
                    ForEach(WindowAction.allCases) { action in
                        Text(action.localizedString).tag(action)
                    }
                }
                .labelsHidden()
                
                Text("Standard behavior: Show")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Else Action
            VStack(alignment: .leading, spacing: 8) {
                Text("In Other Spaces:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                
                Picker("", selection: $workingRule.elseAction) {
                    ForEach(WindowAction.allCases) { action in
                        Text(action.localizedString).tag(action)
                    }
                }
                .labelsHidden()
                
                Text("Standard behavior: Hide or Minimize")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
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

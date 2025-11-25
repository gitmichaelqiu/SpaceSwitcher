import SwiftUI

struct RuleEditor: View {
    @State private var workingRule: AppRule
    let availableSpaces: [RenamerSpace]
    let onSave: (AppRule) -> Void
    let onCancel: () -> Void
    
    // Running Apps List
    @State private var runningApps: [(name: String, id: String, icon: NSImage)] = []
    
    init(rule: AppRule?, availableSpaces: [RenamerSpace], onSave: @escaping (AppRule) -> Void, onCancel: @escaping () -> Void) {
        _workingRule = State(initialValue: rule ?? AppRule(appBundleID: "", appName: "Select App", targetSpaceIDs: [], matchAction: .hide, elseAction: .show))
        self.availableSpaces = availableSpaces
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Rule")
                .font(.title2)
            
            SettingsSection("1. Target App") {
                SettingsRow("Application") {
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
                            if !workingRule.appBundleID.isEmpty,
                               let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            Text(workingRule.appName)
                        }
                    }
                }
            }
            
            SettingsSection("2. Logic") {
                HStack(alignment: .top, spacing: 0) {
                    // Part A: In Spaces...
                    VStack(alignment: .leading) {
                        Text("In these spaces:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
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
                                    .labelsHidden()
                                    
                                    Text("\(space.number). \(space.name)")
                                }
                            }
                        }
                        .frame(height: 100)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .frame(width: 180)
                    
                    Spacer()
                    
                    // Part B: Action
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("Action:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $workingRule.matchAction) {
                                ForEach(WindowAction.allCases) { action in
                                    Text(NSLocalizedString("WindowAction.\(action.rawValue)", comment: "")).tag(action)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading) {
                            Text("Otherwise:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $workingRule.elseAction) {
                                ForEach(WindowAction.allCases) { action in
                                    Text(NSLocalizedString("WindowAction.\(action.rawValue)", comment: "")).tag(action)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .frame(maxWidth: 150)
                }
                .padding(10)
            }
            
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save Rule") {
                    onSave(workingRule)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workingRule.appBundleID.isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
        .onAppear {
            loadRunningApps()
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

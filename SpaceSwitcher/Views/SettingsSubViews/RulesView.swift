import SwiftUI

struct RulesView: View {
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var spaceManager: SpaceManager
    @StateObject private var permissionManager = PermissionManager.shared
    
    @State private var showingAddRule = false
    @State private var selectedRule: AppRule?
    @State private var rulePendingDeletion: AppRule?
    
    var body: some View {
        SettingsContainer(.rules) {
            if ruleManager.rules.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                VStack(spacing: 14) {
                    // Global Toggle
                    SettingsSection {
                        SettingsRow(
                            "Automation",
                            helperText: "When disabled, all automation rules will be ignored.",
                            requirements: [
                                .accessibility(isGranted: permissionManager.isAccessibilityGranted),
                                .inputEvents(isGranted: permissionManager.isEventSynthesisGranted),
                                .spaceAPI(isAvailable: spaceManager.apiAvailability == .available)
                            ]
                        ) {
                            Toggle("", isOn: $ruleManager.isAutomationEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                    
                    ForEach(ruleManager.rules) { rule in
                        SettingsSection {
                            RuleRow(
                                rule: rule,
                                availableSpaces: spaceManager.availableSpaces,
                                isGlobalEnabled: ruleManager.isAutomationEnabled,
                                onEdit: { selectedRule = rule },
                                onDelete: { rulePendingDeletion = rule },
                                onToggle: { updatedRule in
                                    ruleManager.updateRule(updatedRule)
                                }
                            )
                        }
                        .transition(.opacity)
                    }
                    
                    Button {
                        showingAddRule = true
                    } label: {
                        Label("Add New Rule", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .animation(.easeInOut(duration: 0.2), value: ruleManager.rules)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddRuleRequest"))) { _ in
            showingAddRule = true
        }
        .sheet(isPresented: $showingAddRule) {
            RuleEditor(
                rule: AppRule(appBundleID: "", appName: "", groups: [], elseActions: []),
                availableSpaces: spaceManager.availableSpaces,
                onSave: { newRule in
                    withAnimation {
                        ruleManager.addRule(newRule)
                        showingAddRule = false
                    }
                },
                onCancel: { showingAddRule = false }
            )
        }
        .sheet(item: $selectedRule) { rule in
            RuleEditor(
                rule: rule,
                availableSpaces: spaceManager.availableSpaces,
                onSave: { updatedRule in
                    withAnimation {
                        ruleManager.updateRule(updatedRule)
                        selectedRule = nil
                    }
                },
                onCancel: { selectedRule = nil }
            )
        }
        .confirmationDialog(
            "Delete Rule?",
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { rulePendingDeletion = nil }
                }
            )
        ) {
            Button("Delete Rule", role: .destructive) {
                if let rule = rulePendingDeletion {
                    withAnimation {
                        ruleManager.deleteRule(rule)
                    }
                }
                rulePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                rulePendingDeletion = nil
            }
        } message: {
            Text("This removes the rule for \(rulePendingDeletion?.appName ?? "this application").")
        }
    }
    
    private var emptyState: some View {
        Group {
            if #available(macOS 14.0, *) {
                ContentUnavailableView {
                    Label("No automation rules yet.", systemImage: "list.bullet.rectangle.portrait")
                } description: {
                    Text("Create a rule to control applications by desktop space.")
                } actions: {
                    Button("Create First Rule") {
                        showingAddRule = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No automation rules yet.")
                        .foregroundStyle(.secondary)
                    Button("Create First Rule") {
                        showingAddRule = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
}

struct RuleRow: View {
    let rule: AppRule
    let availableSpaces: [SpaceInfo]
    let isGlobalEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: (AppRule) -> Void
    
    private func spacesString(for spaceIDs: Set<String>) -> String {
        let items = spaceIDs.compactMap { id -> String? in
            if let space = availableSpaces.first(where: { $0.id == id }) {
                // Return just the name if it exists, otherwise "Space X"
                return space.name.isEmpty ? "Space \(space.number)" : space.name
            }
            return nil
        }.sorted()
        
        if items.isEmpty { return "Unassigned" }
        return items.joined(separator: ", ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                appIcon
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.appName.isEmpty ? "Select Application" : rule.appName)
                        .font(.body.weight(.semibold))
                    Text(rule.appBundleID.isEmpty ? "No application selected" : rule.appBundleID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Edit", systemImage: "pencil", action: onEdit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Toggle("Enabled", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { value in
                        var updatedRule = rule
                        updatedRule.isEnabled = value
                        onToggle(updatedRule)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isGlobalEnabled)
                .help(isGlobalEnabled ? "Enable or disable this rule." : "Enable Automation above to use individual rules.")

                Menu {
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .help("Rule Actions")
            }
            .padding(12)

            if !rule.groups.isEmpty || !rule.elseActions.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rule.groups) { group in
                        ruleSummary(
                            icon: "arrow.up.forward.app",
                            title: spacesString(for: group.targetSpaceIDs),
                            details: actionSummary(group.actions)
                        )

                        if rule.groups.last?.id != group.id || !rule.elseActions.isEmpty {
                            Divider()
                        }
                    }

                    if !rule.elseActions.isEmpty {
                        ruleSummary(
                            icon: "ellipsis.circle",
                            title: "Otherwise",
                            details: actionSummary(rule.elseActions)
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private var appIcon: some View {
        Group {
            if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.appBundleID)?.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionSummary(_ actions: [ActionItem]) -> String {
        actions.isEmpty ? "No actions" : actions.map { $0.value.localizedString }.joined(separator: ", ")
    }

    private func ruleSummary(icon: String, title: String, details: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}

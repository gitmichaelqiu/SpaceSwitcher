import SwiftUI

struct RulesView: View {
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var showingAddRule = false
    @State private var selectedRule: AppRule?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            if ruleManager.rules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(ruleManager.rules) { rule in
                            SettingsSection {
                                RuleRow(
                                    rule: rule,
                                    availableSpaces: spaceManager.availableSpaces,
                                    onEdit: { selectedRule = rule },
                                    onDelete: {
                                        withAnimation {
                                            ruleManager.deleteRule(rule)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(20)
                }
            }
            
            Spacer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddRuleRequest"))) { _ in
            showingAddRule = true
        }
        .sheet(isPresented: $showingAddRule) {
            RuleEditor(
                rule: AppRule(appBundleID: "", appName: "", groups: [], elseActions: []),
                availableSpaces: spaceManager.availableSpaces,
                onSave: { newRule in
                    ruleManager.addRule(newRule)
                    showingAddRule = false
                },
                onCancel: { showingAddRule = false }
            )
        }
        .sheet(item: $selectedRule) { rule in
            RuleEditor(
                rule: rule,
                availableSpaces: spaceManager.availableSpaces,
                onSave: { updatedRule in
                    ruleManager.updateRule(updatedRule)
                    selectedRule = nil
                },
                onCancel: { selectedRule = nil }
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("No automation rules yet.")
                .font(.body)
                .foregroundColor(.secondary)
            
            Button("Create First Rule") {
                showingAddRule = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
}

struct RuleRow: View {
    let rule: AppRule
    let availableSpaces: [SpaceInfo]
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    // App Icon
                    if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.appBundleID)?.path {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    } else {
                        Image(systemName: "questionmark.app.dashed")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rule.appName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(rule.appBundleID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(8)
                                .background(Circle().fill(Color.accentColor.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(8)
                                .background(Circle().fill(Color.red.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                    .opacity(isHovering ? 1.0 : 0.0)
                }
                
                if !rule.groups.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Workflows")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(.secondary.opacity(0.8))
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(rule.groups) { group in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "arrow.up.forward.app.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.accentColor.opacity(0.8))
                                        .padding(.top, 2)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(spacesString(for: group.targetSpaceIDs))
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.primary.opacity(0.9))
                                        
                                        Text(group.actions.map { $0.value.localizedString }.joined(separator: ", "))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            
                            if !rule.elseActions.isEmpty {
                                Divider().opacity(0.2).padding(.vertical, 2)
                                
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "ellipsis.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary.opacity(0.6))
                                        .padding(.top, 2)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Otherwise")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.secondary)
                                        
                                        Text(rule.elseActions.map { $0.value.localizedString }.joined(separator: ", "))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                    )
                }
            }
            .padding(12)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

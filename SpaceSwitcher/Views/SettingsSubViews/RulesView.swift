import SwiftUI

struct RulesView: View {
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var showingAddRule = false
    @State private var selectedRule: AppRule?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with Action
            HStack {
                Text("AUTOMATION RULES")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    showingAddRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)
            
            if ruleManager.rules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(ruleManager.rules) { rule in
                            RuleRow(rule: rule, onEdit: { selectedRule = rule }, onDelete: {
                                withAnimation {
                                    ruleManager.deleteRule(rule)
                                }
                            })
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            
            Spacer()
        }
        .padding()
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
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        SettingsSection {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    // App Icon
                    if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.appBundleID)?.path {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 40, height: 40)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    } else {
                        Image(systemName: "questionmark.app.dashed")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.appName)
                            .font(.system(size: 15, weight: .bold))
                        Text(rule.appBundleID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
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
                
                // RESTORED: Workflow Summary
                if !rule.groups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WORKFLOWS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        ForEach(rule.groups) { group in
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor.opacity(0.6))
                                
                                Text("\(group.targetSpaceIDs.count) Spaces")
                                    .font(.system(size: 11, weight: .semibold))
                                
                                Text("→")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.5))
                                
                                Text(group.actions.map { $0.value.localizedString }.joined(separator: ", "))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        if !rule.elseActions.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.6))
                                
                                Text("Otherwise:")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Text(rule.elseActions.map { $0.value.localizedString }.joined(separator: ", "))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                }
            }
            .padding(12)
        }
        .onHover { isHovering = $0 }
    }
}

import SwiftUI

struct RulesView: View {
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var spaceManager: SpaceManager
    @State private var editingRule: AppRule?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Rules")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
                
                Spacer()
                
                Picker("", selection: $ruleManager.sortOption) {
                    ForEach(RuleSortOption.allCases) { option in
                        Text("Sort by \(option.rawValue)").tag(option)
                    }
                }
                .controlSize(.small)
                .frame(width: 130)
                .labelsHidden()
            }
            .padding(.horizontal, 4)
            
            // MARK: - List Content
            Group {
                if ruleManager.rules.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.2))
                        
                        VStack(spacing: 4) {
                            Text("No Rules Configured")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Add a rule to control app behavior across spaces.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                            )
                    )
                } else {
                    List {
                        ForEach(ruleManager.sortedRules) { rule in
                            RuleRow(
                                rule: rule,
                                spaces: spaceManager.availableSpaces,
                                onDelete: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        ruleManager.deleteRule(withID: rule.id)
                                    }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { editingRule = rule }
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 400)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                            )
                    )
                }
            }
            
            // MARK: - Actions
            HStack(spacing: 12) {
                Button {
                    spaceManager.refreshSpaceList()
                } label: {
                    Label("Refresh Spaces", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Button {
                    editingRule = AppRule(
                        appBundleID: "",
                        appName: NSLocalizedString("Select Target App", comment: ""),
                        groups: [RuleGroup(targetSpaceIDs: [], actions: [])],
                        elseActions: [ActionItem(.hide)]
                    )
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Rule")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditor(rule: rule, availableSpaces: spaceManager.availableSpaces, onSave: { newRule in
                if let index = ruleManager.rules.firstIndex(where: { $0.id == newRule.id }) {
                    ruleManager.rules[index] = newRule
                } else {
                    ruleManager.rules.append(newRule)
                }
                editingRule = nil
            }, onCancel: { editingRule = nil })
        }
    }
}

struct RuleRow: View {
    let rule: AppRule
    let spaces: [SpaceInfo]
    let onDelete: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon
            if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.appBundleID)?.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(2)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(rule.appName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(rule.groups.indices, id: \.self) { idx in
                        let group = rule.groups[idx]
                        HStack(spacing: 4) {
                            Text("In").foregroundColor(.secondary)
                            Text(formatSpaces(group.targetSpaceIDs))
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("→").foregroundColor(.secondary)
                            Text(formatActions(group.actions))
                                .foregroundColor(.accentColor)
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 11))
                    }
                    
                    HStack(spacing: 4) {
                        Text("Else").foregroundColor(.secondary)
                        Text("→").foregroundColor(.secondary)
                        Text(formatActions(rule.elseActions))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .font(.system(size: 11))
                }
            }
            
            Spacer()
            
            // Trash Button
            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isHovering ? .red : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hover
            }
        }
    }
    
    func formatSpaces(_ ids: Set<String>) -> String {
        if ids.isEmpty { return "None" }
        let matched = spaces.filter { ids.contains($0.id) }.sorted { $0.number < $1.number }
        if matched.isEmpty { return "\(ids.count) Space(s)" }
        return matched.map { $0.name }.joined(separator: ", ")
    }
    
    func formatActions(_ actions: [ActionItem]) -> String {
        if actions.isEmpty { return "Nothing" }
        return actions.map { $0.value.localizedString }.joined(separator: " + ")
    }
}

import SwiftUI

struct RulesView: View {
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var spaceManager: SpaceManager
    @State private var editingRule: AppRule?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("App Rules").font(.headline)
                Spacer()
                Picker("", selection: $ruleManager.sortOption) {
                    ForEach(RuleSortOption.allCases) { option in Text("Sort by \(option.rawValue)").tag(option) }
                }
                .frame(width: 140).labelsHidden()
            }
            .padding(.top, 10)
            
            if ruleManager.rules.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle.portrait").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("No Rules Configured").font(.title3).foregroundColor(.secondary)
                    Text("Add a rule to control app visibility across spaces.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            } else {
                List {
                    ForEach(ruleManager.sortedRules) { rule in
                        RuleRow(rule: rule, spaces: spaceManager.availableSpaces, onDelete: { withAnimation { ruleManager.deleteRule(withID: rule.id) } })
                            .contentShape(Rectangle())
                            .onTapGesture { editingRule = rule }
                    }
                }
                .listStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
            }
            
            HStack {
                Button { spaceManager.refreshSpaceList() } label: { Label("Refresh Spaces", systemImage: "arrow.clockwise") }
                Spacer()
                // FIX: Initialize new rule with empty actions (Do Nothing by default)
                Button {
                    editingRule = AppRule(
                        appBundleID: "",
                        appName: NSLocalizedString("Select Target App", comment: ""),
                        targetSpaceIDs: [],
                        matchActions: [],
                        elseActions: []
                    )
                } label: { Text("+ Add Rule").frame(minWidth: 80) }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditor(rule: rule, availableSpaces: spaceManager.availableSpaces, onSave: { newRule in
                if let index = ruleManager.rules.firstIndex(where: { $0.id == newRule.id }) { ruleManager.rules[index] = newRule }
                else { ruleManager.rules.append(newRule) }
                editingRule = nil
            }, onCancel: { editingRule = nil })
        }
    }
}

// RuleRow remains largely the same, logic works for empty arrays too
struct RuleRow: View {
    let rule: AppRule
    let spaces: [SpaceInfo]
    let onDelete: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.appBundleID)?.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.dashed").resizable().frame(width: 32, height: 32).foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.appName).font(.headline).foregroundColor(.primary)
                HStack(spacing: 4) {
                    Text("In").foregroundColor(.secondary)
                    Text(formatSpaces(rule.targetSpaceIDs)).fontWeight(.medium).foregroundColor(.primary)
                    Text("→").foregroundColor(.secondary).font(.caption)
                    Text(formatActions(rule.matchActions)).foregroundColor(.green).fontWeight(.semibold)
                    Text("• else").foregroundColor(.secondary)
                    Text(formatActions(rule.elseActions)).foregroundColor(.red)
                }
                .font(.caption)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash").foregroundColor(isHovering ? .red : .secondary.opacity(0.5)).font(.system(size: 14))
            }
            .buttonStyle(.plain).opacity(isHovering ? 1 : 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(isHovering ? Color.secondary.opacity(0.05) : Color.clear)
        .cornerRadius(6)
        .onHover { hover in withAnimation(.easeInOut(duration: 0.15)) { isHovering = hover } }
    }
    
    func formatSpaces(_ ids: Set<String>) -> String {
        if ids.isEmpty { return "None" }
        let matched = spaces.filter { ids.contains($0.id) }.sorted { $0.number < $1.number }
        if matched.isEmpty { return "\(ids.count) Space(s)" }
        return matched.map { $0.name }.joined(separator: ", ")
    }
    
    func formatActions(_ actions: [WindowAction]) -> String {
        if actions.isEmpty { return "Nothing" }
        return actions.map { $0.localizedString.lowercased() }.joined(separator: " + ")
    }
}

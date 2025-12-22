import SwiftUI

struct RulesView: View {
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var spaceManager: SpaceManager
    @State private var showingEditor = false
    @State private var selectedRuleID: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Header & Sort Controls
            HStack {
                Text("App Rules")
                    .font(.headline)
                
                Spacer()
                
                Picker("", selection: $ruleManager.sortOption) {
                    ForEach(RuleSortOption.allCases) { option in
                        Text("Sort by \(option.rawValue)").tag(option)
                    }
                }
                .frame(width: 140)
                .labelsHidden()
            }
            .padding(.top, 10)
            
            // MARK: - Rules List
            if ruleManager.rules.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Rules Configured")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Add a rule to control app visibility across spaces.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            } else {
                List {
                    // Use sortedRules instead of raw rules binding
                    ForEach(ruleManager.sortedRules) { rule in
                        RuleRow(
                            rule: rule,
                            spaces: spaceManager.availableSpaces,
                            onDelete: {
                                withAnimation {
                                    ruleManager.deleteRule(withID: rule.id)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedRuleID = rule.id
                            showingEditor = true
                        }
                    }
                }
                .listStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
            }
            
            // MARK: - Footer Actions
            HStack {
                Button {
                    spaceManager.refreshSpaceList()
                } label: {
                    Label("Refresh Spaces", systemImage: "arrow.clockwise")
                }
                .help("Reload space list from DesktopRenamer")
                
                Spacer()
                
                Button {
                    selectedRuleID = nil
                    showingEditor = true
                } label: {
                    Text("+ Add Rule")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .sheet(isPresented: $showingEditor) {
            RuleEditor(
                rule: selectedRuleID == nil ? nil : ruleManager.rules.first(where: { $0.id == selectedRuleID }),
                availableSpaces: spaceManager.availableSpaces,
                onSave: { newRule in
                    if let index = ruleManager.rules.firstIndex(where: { $0.id == newRule.id }) {
                        ruleManager.rules[index] = newRule
                    } else {
                        ruleManager.rules.append(newRule)
                    }
                    showingEditor = false
                },
                onCancel: {
                    showingEditor = false
                }
            )
        }
    }
}

struct RuleRow: View {
    let rule: AppRule
    let spaces: [SpaceInfo]
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.appBundleID)?.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.secondary)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.appName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text("In")
                        .foregroundColor(.secondary)
                    Text(formatSpaces(rule.targetSpaceIDs))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("→")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text(rule.matchAction.localizedString.lowercased())
                        .foregroundColor(colorForAction(rule.matchAction))
                        .fontWeight(.semibold)
                    
                    Text("• else")
                        .foregroundColor(.secondary)
                    
                    Text(rule.elseAction.localizedString.lowercased())
                        .foregroundColor(colorForAction(rule.elseAction))
                }
                .font(.caption)
            }
            
            Spacer()
            
            // Delete Button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(isHovering ? .red : .secondary.opacity(0.5))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0) // Only visible on hover (cleaner look)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isHovering ? Color.secondary.opacity(0.05) : Color.clear)
        .cornerRadius(6)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hover
            }
        }
    }
    
    func formatSpaces(_ ids: Set<String>) -> String {
        if ids.isEmpty { return "None" }
        
        // Match IDs to SpaceInfo to get proper Names/Numbers
        let matched = spaces.filter { ids.contains($0.id) }.sorted { $0.number < $1.number }
        
        if matched.isEmpty {
            // IDs exist but not currently connected
            return "\(ids.count) Space(s)"
        }
        
        let names = matched.map { $0.name }
        return names.joined(separator: ", ")
    }
    
    func colorForAction(_ action: WindowAction) -> Color {
        switch action {
        case .show: return .green
        case .hide: return .red
        case .doNothing: return .secondary
        case .minimize: return .orange
        }
    }
}

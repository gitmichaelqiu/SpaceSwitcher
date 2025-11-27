import SwiftUI

struct RulesView: View {
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var spaceManager: SpaceManager
    @State private var showingEditor = false
    @State private var selectedRuleID: UUID?
    
    var body: some View {
        VStack(alignment: .leading) {
            if ruleManager.rules.isEmpty {
                VStack {
                    Spacer()
                    Text("No Rules Configured")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Click + to add a new switching rule.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach($ruleManager.rules) { $rule in
                        RuleRow(rule: rule, spaces: spaceManager.availableSpaces)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedRuleID = rule.id
                                showingEditor = true
                            }
                    }
                    .onDelete { indexSet in
                        ruleManager.rules.remove(atOffsets: indexSet)
                    }
                }
            }
            
            HStack {
                Button {
                    spaceManager.refreshSpaceList()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Space List")
                
                Spacer()
                
                Button("+ Add Rule") {
                    selectedRuleID = nil
                    showingEditor = true
                }
            }
            .padding(.top, 8)
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
    let spaces: [RenamerSpace]
    
    var body: some View {
        HStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.appBundleID)?.path ?? ""))
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading) {
                Text(rule.appName)
                    .font(.headline)
                
                HStack(spacing: 4) {
                    Text("In")
                    Text(formatSpaces(rule.targetSpaceIDs))
                        .fontWeight(.medium)
                    Text(rule.matchAction.localizedString.lowercased())
                        .foregroundColor(colorForAction(rule.matchAction))
                    
                    Text("• else")
                        .foregroundColor(.secondary)
                    
                    Text(rule.elseAction.localizedString.lowercased())
                        .foregroundColor(colorForAction(rule.elseAction))
                }
                .font(.caption)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    func formatSpaces(_ ids: Set<String>) -> String {
        if ids.isEmpty { return "None" }
        let names = ids.compactMap { id in spaces.first(where: { $0.id == id })?.name }
        if names.isEmpty { return String(format: NSLocalizedString("SpaceCount", comment: ""), ids.count) }
        return names.joined(separator: ", ")
    }
    
    func colorForAction(_ action: WindowAction) -> Color {
        switch action {
        case .show: return .green
        case .hide: return .red
        case .doNothing: return .secondary
        }
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RulesView: View {
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var spaceManager: SpaceManager
    @StateObject private var permissionManager = PermissionManager.shared
    
    @State private var presentedRuleSheet: RuleSheet?
    @State private var rulePendingDeletion: AppRule?
    @State private var showingImportPicker = false
    @State private var showingTransferError = false
    @State private var transferErrorMessage = ""

    private enum RuleSheet: Identifiable {
        case add(AppRule)
        case edit(AppRule)
        case importOptions([AppRule])

        var id: String {
            switch self {
            case .add(let rule): return "add-\(rule.id.uuidString)"
            case .edit(let rule): return "edit-\(rule.id.uuidString)"
            case .importOptions: return "import-options"
            }
        }
    }
    
    var body: some View {
        SettingsContainer(.rules) {
            VStack(spacing: SettingsComponentMetrics.sectionSpacing) {
                automationSection
                perAppAutomationSection

                if !ruleManager.rules.isEmpty {
                    Button {
                        presentNewRuleEditor()
                    } label: {
                        Label("Add new rule", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: ruleManager.rules)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddRuleRequest"))) { _ in
            presentNewRuleEditor()
        }
        .sheet(item: $presentedRuleSheet) { sheet in
            switch sheet {
            case .add(let rule):
                RuleEditor(
                    rule: rule,
                    availableSpaces: spaceManager.availableSpaces,
                    onSave: { newRule in
                        withAnimation {
                            ruleManager.addRule(newRule)
                            presentedRuleSheet = nil
                        }
                    },
                    onCancel: { presentedRuleSheet = nil }
                )
            case .edit(let rule):
                RuleEditor(
                    rule: rule,
                    availableSpaces: spaceManager.availableSpaces,
                    onSave: { updatedRule in
                        withAnimation {
                            ruleManager.updateRule(updatedRule)
                            presentedRuleSheet = nil
                        }
                    },
                    onCancel: { presentedRuleSheet = nil }
                )
            case .importOptions(let importedRules):
                ImportRulesOptionsView(
                    onImport: { strategy in
                        applyImportedRules(importedRules, using: strategy)
                    },
                    onCancel: { presentedRuleSheet = nil }
                )
            }
        }
        .confirmationDialog(
            "Delete rule?",
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { rulePendingDeletion = nil }
                }
            )
        ) {
            Button("Delete rule", role: .destructive) {
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
            Text("This removes the rule for \(pendingDeletionApplicationName).")
        }
        .alert("Rule transfer failed", isPresented: $showingTransferError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(transferErrorMessage)
        }
    }

    private var automationSection: some View {
        SettingsSection("Automation") {
            SettingsRow(
                "Automatically switch spaces",
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
    }

    private var perAppAutomationSection: some View {
        VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionSpacing) {
            HStack(spacing: 8) {
                SettingsSectionTitle(
                    "Per-App Automation",
                    helperText: "Rules are evaluated from top to bottom. The first matching rule wins."
                )

                Spacer(minLength: 12)

                importRulesButton

                Button("Export", systemImage: "square.and.arrow.up", action: exportRules)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(ruleManager.rules.isEmpty)
            }

            if ruleManager.rules.isEmpty {
                SettingsSection {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 280)
                }
            } else {
                ReorderableSettingsList(
                    items: reorderableRules,
                    rowContent: { item, context in
                        SettingsSection {
                            RuleRow(
                                rule: item.rule,
                                availableSpaces: spaceManager.availableSpaces,
                                onEdit: { presentedRuleSheet = .edit(item.rule) },
                                onDelete: { rulePendingDeletion = item.rule },
                                onToggle: { updatedRule in
                                    ruleManager.updateRule(updatedRule)
                                }
                            )
                        }
                        .padding(
                            .bottom,
                            context.isLast ? 0 : SettingsComponentMetrics.sectionSpacing
                        )
                    },
                    dragPreview: { item in
                        SettingsSection {
                            RuleRow(
                                rule: item.rule,
                                availableSpaces: spaceManager.availableSpaces,
                                onEdit: {},
                                onDelete: {},
                                onToggle: { _ in }
                            )
                        }
                        .frame(minWidth: 420)
                    },
                    moveBefore: { sourceID, targetID in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            ruleManager.moveRule(sourceID: sourceID, before: targetID)
                        }
                    },
                    moveToEnd: { sourceID in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            _ = ruleManager.moveRuleToEnd(sourceID: sourceID)
                        }
                    }
                )
            }
        }
    }

    private var importRulesButton: some View {
        Button("Import", systemImage: "square.and.arrow.down") {
            showingImportPicker = true
        }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onCompletion: handleImportSelection
            )
    }

    private var reorderableRules: [ReorderableRule] {
        ruleManager.rules.map(ReorderableRule.init)
    }
    
    private var emptyState: some View {
        Group {
            if #available(macOS 14.0, *) {
                ContentUnavailableView {
                    Label("No automation rules yet.", systemImage: "list.bullet.rectangle.portrait")
                } description: {
                    Text("Create a rule to control applications by desktop space.")
                } actions: {
                    Button("Create first rule") {
                        presentNewRuleEditor()
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
                    Button("Create first rule") {
                        presentNewRuleEditor()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private func presentNewRuleEditor() {
        presentedRuleSheet = .add(
            AppRule(appBundleID: "", appName: "", groups: [], elseActions: [])
        )
    }

    private func exportRules() {
        do {
            let data = try RuleTransferService.encode(ruleManager.rules)
            let panel = NSSavePanel()
            panel.title = NSLocalizedString("Export Rules", comment: "Title of the export rules file panel")
            panel.nameFieldStringValue = "SpaceSwitcher-Rules.json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    showTransferError(error)
                }
            }
        } catch {
            showTransferError(error)
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let importedRules = try RuleTransferService.decode(Data(contentsOf: url))
                presentedRuleSheet = .importOptions(importedRules)
            } catch {
                showTransferError(error)
            }
        case .failure(let error):
            showTransferError(error)
        }
    }

    private func applyImportedRules(_ importedRules: [AppRule], using strategy: RuleImportStrategy) {
        withAnimation {
            ruleManager.rules = RuleTransferService.applying(
                importedRules,
                to: ruleManager.rules,
                strategy: strategy
            )
        }
        presentedRuleSheet = nil
    }

    private func showTransferError(_ error: Error) {
        let message = error.localizedDescription
        DispatchQueue.main.async {
            transferErrorMessage = message
            showingTransferError = true
        }
    }

    private var pendingDeletionApplicationName: String {
        guard let rule = rulePendingDeletion else { return "this application" }
        if rule.appliesToAllApps {
            return NSLocalizedString("All apps", comment: "")
        }
        guard !rule.appBundleID.isEmpty else { return rule.appName }
        return resolvedApplicationName(
            bundleIdentifier: rule.appBundleID,
            storedName: rule.appName
        )
    }
}

private struct ImportRulesOptionsView: View {
    let onImport: (RuleImportStrategy) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose how to import rules")
                    .font(.title2.weight(.semibold))

                Text("Choose how imported rules should interact with your current rules.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                optionButton(
                    "Keep All Rules",
                    description: "Append every imported rule, even for apps that already have rules.",
                    systemImage: "plus.square.on.square",
                    strategy: .keepAll
                )
                optionButton(
                    "Add Rules for New Apps",
                    description: "Add rules only for apps that don't already have rules.",
                    systemImage: "plus.circle",
                    strategy: .addNewApps
                )
                optionButton(
                    "Replace Rules for Matching Apps",
                    description: "Replace rules for imported apps and keep rules for other apps.",
                    systemImage: "arrow.triangle.2.circlepath",
                    strategy: .replaceMatchingApps,
                    isDestructive: true
                )
                optionButton(
                    "Replace All Rules",
                    description: "Replace all current rules with the imported rules.",
                    systemImage: "trash",
                    strategy: .replaceAll,
                    isDestructive: true
                )
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func optionButton(
        _ title: LocalizedStringKey,
        description: LocalizedStringKey,
        systemImage: String,
        strategy: RuleImportStrategy,
        isDestructive: Bool = false
    ) -> some View {
        Button {
            onImport(strategy)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(isDestructive ? Color.red : Color.accentColor)
                    .frame(width: 22, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isDestructive ? Color.red : Color.primary)

                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ReorderableRule: Identifiable {
    let rule: AppRule

    var id: String {
        rule.id.uuidString
    }
}

struct RuleRow: View {
    let rule: AppRule
    let availableSpaces: [SpaceInfo]
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: (AppRule) -> Void
    
    private func spacesString(for group: RuleGroup) -> String {
        var items = group.targetSpaceIDs.compactMap { id -> String? in
            if let space = availableSpaces.first(where: { $0.id == id }) {
                return spaceDisplayName(space)
            }
            return nil
        }.sorted()

        if group.usesSourceSpace {
            items.insert(
                String(localized: "Source space", comment: "Special rule condition matching a window's current desktop"),
                at: 0
            )
        }

        if items.isEmpty { return "Unassigned" }
        return items.joined(separator: ", ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 20)
                    .accessibilityLabel("Drag to rearrange")

                appIcon
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if rule.appliesToAllApps {
                            Text("All apps")
                        } else if rule.appBundleID.isEmpty {
                            Text("Select application")
                        } else {
                            Text(resolvedApplicationName(
                                bundleIdentifier: rule.appBundleID,
                                storedName: rule.appName
                            ))
                        }
                    }
                    .font(.body.weight(.semibold))

                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { value in
                        var updatedRule = rule
                        updatedRule.isEnabled = value
                        onToggle(updatedRule)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Enable or disable this rule.")
                .accessibilityLabel("Enable rule")

                Button("Edit", systemImage: "pencil", action: onEdit)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Edit rule")

                Button(role: .destructive, action: onDelete) {
                    SettingsDestructiveIconLabel(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Delete rule")
                .accessibilityLabel("Delete rule")
            }
            .padding(.horizontal, SettingsComponentMetrics.rowHorizontalPadding)
            .padding(.vertical, SettingsComponentMetrics.rowVerticalPadding)
            .frame(height: SettingsComponentMetrics.listRowHeight, alignment: .center)

            if !rule.groups.isEmpty || !rule.elseActions.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rule.groups) { group in
                        ruleSummary(
                            icon: "arrow.up.forward.app",
                            title: spacesString(for: group),
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
            if rule.appliesToAllApps {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.appBundleID)?.path {
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
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

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

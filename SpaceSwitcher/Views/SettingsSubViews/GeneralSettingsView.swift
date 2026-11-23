import AppKit
import SwiftUI
import Sparkle
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var contextualHotkeyManager: ContextualHotkeyManager

    @State private var launchAtLogin: Bool = LaunchManager.isEnabled
    @StateObject private var menuBarIconSettings = MenuBarIconSettings.shared
    @StateObject private var hudToastSettings = HUDToastSettings.shared
    @State private var autoCheckUpdate: Bool = UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates
    @State private var autoDownloadUpdate: Bool = UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates
    @State private var showingImportPicker = false
    @State private var showingExportPicker = false
    @State private var showingImportOptions = false
    @State private var exportDocument: SettingsExportDocument?
    @State private var importedSettings: ImportedSettings?
    @State private var showingTransferError = false
    @State private var transferErrorMessage = ""

    init(ruleManager: RuleManager, contextualHotkeyManager: ContextualHotkeyManager) {
        self.ruleManager = ruleManager
        self.contextualHotkeyManager = contextualHotkeyManager
    }

    var body: some View {
        SettingsContainer(.general) {
            VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionSpacing) {
                // 1. General
                SettingsSection("General") {
                    SettingsRow("Launch at login") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { value in
                                LaunchManager.setEnabled(value)
                            }
                    }
                }

                // 2. Menu Bar
                SettingsSection("Menu Bar") {
                    SettingsRow("Show menu bar icon") {
                        Toggle("", isOn: Binding(
                            get: { !menuBarIconSettings.isHidden },
                            set: { menuBarIconSettings.isHidden = !$0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow("Show HUD toasts") {
                        Toggle("", isOn: Binding(
                            get: { hudToastSettings.isEnabled },
                            set: { isEnabled in
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    hudToastSettings.isEnabled = isEnabled
                                }
                            }
                        ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if hudToastSettings.isEnabled {
                        VStack(spacing: 0) {
                            Divider()

                            SettingsRow("Rule HUD toasts") {
                                Toggle("", isOn: $hudToastSettings.isRuleHUDEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }

                            Divider()

                            SettingsRow("Dock switch HUD toasts") {
                                Toggle("", isOn: $hudToastSettings.isDockHUDEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                
                // 3. Updates - Standardized per macOSers bundle
                SettingsSection("Updates") {
                    SettingsRow("Automatically check for updates") {
                        Toggle("", isOn: $autoCheckUpdate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoCheckUpdate) { value in
                                UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates = value
                            }
                    }
                    
                    Divider()
                    
                    if autoCheckUpdate {
                        SettingsRow("Automatically download updates") {
                            Toggle("", isOn: $autoDownloadUpdate)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .onChange(of: autoDownloadUpdate) { value in
                                    UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates = value
                                }
                        }
                        Divider()
                    }
                    
                    SettingsRow("Check for updates") {
                        Button("Check now") {
                            UpdateManager.shared.updaterController.checkForUpdates(nil)
                        }
                    }
                }

                SettingsSection("Import and Export") {
                    SettingsRow("Rules and hotkeys") {
                        HStack(spacing: 8) {
                            importButton
                            exportButton
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $showingImportOptions, onDismiss: {
            importedSettings = nil
        }) {
            if let importedSettings {
                ImportSettingsOptionsView(
                    importedSettings: importedSettings,
                    onImport: { strategy in
                        applyImportedSettings(importedSettings, using: strategy)
                    },
                    onCancel: { showingImportOptions = false }
                )
            }
        }
        .alert("Settings transfer failed", isPresented: $showingTransferError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(transferErrorMessage)
        }
        .animation(.easeInOut(duration: 0.2), value: autoCheckUpdate)
        .onAppear {
            launchAtLogin = LaunchManager.isEnabled
        }
    }

    private var importButton: some View {
        Button("Import") {
            showingImportPicker = true
        }
        .buttonStyle(.bordered)
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
    }

    private var exportButton: some View {
        Button("Export", action: exportSettings)
            .buttonStyle(.bordered)
            .disabled(ruleManager.rules.isEmpty && contextualHotkeyManager.hotkeys.isEmpty)
            .fileExporter(
                isPresented: $showingExportPicker,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "SpaceSwitcher-Settings.json",
                onCompletion: handleExportCompletion
            )
    }

    private func exportSettings() {
        do {
            let data = try SettingsTransferService.encode(
                rules: ruleManager.rules,
                hotkeys: contextualHotkeyManager.hotkeys
            )
            exportDocument = SettingsExportDocument(data: data)
            showingExportPicker = true
        } catch {
            showTransferError(error)
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            let nsError = error as NSError
            guard !(error is CancellationError)
                    && !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError)
            else { return }
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
                importedSettings = try SettingsTransferService.decode(Data(contentsOf: url))
                showingImportOptions = true
            } catch {
                showTransferError(error)
            }
        case .failure(let error):
            showTransferError(error)
        }
    }

    private func applyImportedSettings(
        _ importedSettings: ImportedSettings,
        using strategy: RuleImportStrategy
    ) {
        withAnimation {
            if let rules = importedSettings.rules {
                ruleManager.rules = RuleTransferService.applying(
                    rules,
                    to: ruleManager.rules,
                    strategy: strategy
                )
            }
            if let hotkeys = importedSettings.hotkeys {
                contextualHotkeyManager.hotkeys = SettingsTransferService.applying(
                    hotkeys,
                    to: contextualHotkeyManager.hotkeys,
                    strategy: strategy
                )
            }
        }
        showingImportOptions = false
    }

    private func showTransferError(_ error: Error) {
        let message = error.localizedDescription
        DispatchQueue.main.async {
            transferErrorMessage = message
            showingTransferError = true
        }
    }
}

private struct SettingsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ImportSettingsOptionsView: View {
    let importedSettings: ImportedSettings
    let onImport: (RuleImportStrategy) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose how to import settings")
                    .font(.title2.weight(.semibold))

                Text(contentsSummary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                optionButton(
                    "Keep All",
                    description: "Append every imported rule and hotkey, including duplicates.",
                    systemImage: "plus.square.on.square",
                    strategy: .keepAll
                )
                optionButton(
                    "Add New",
                    description: "Add new rules and hotkey entries; skip ones already present.",
                    systemImage: "plus.circle",
                    strategy: .addNewApps
                )
                optionButton(
                    "Replace Matching",
                    description: "Replace rules for matching apps and hotkey entries; keep the rest.",
                    systemImage: "arrow.triangle.2.circlepath",
                    strategy: .replaceMatchingApps,
                    isDestructive: true
                )
                optionButton(
                    "Replace All",
                    description: "Replace current rules and hotkeys included in this file.",
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

    private var contentsSummary: String {
        var sections: [String] = []
        if let rules = importedSettings.rules {
            sections.append("\(rules.count) rules")
        }
        if let hotkeys = importedSettings.hotkeys {
            sections.append("\(hotkeys.count) hotkeys")
        }
        return sections.joined(separator: " · ")
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

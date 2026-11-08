import SwiftUI
import Sparkle

struct GeneralSettingsView: View {
    @State private var launchAtLogin: Bool = LaunchManager.isEnabled
    @StateObject private var menuBarIconSettings = MenuBarIconSettings.shared
    @StateObject private var hudToastSettings = HUDToastSettings.shared
    @State private var autoCheckUpdate: Bool = UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates
    @State private var autoDownloadUpdate: Bool = UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates

    var body: some View {
        SettingsContainer(.general) {
            VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionSpacing) {
                // 1. General
                SettingsSection("General") {
                    SettingsRow("Hide menu bar icon") {
                        Toggle("", isOn: $menuBarIconSettings.isHidden)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow("Show HUD toasts") {
                        Toggle("", isOn: $hudToastSettings.isEnabled)
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
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Divider()

                    SettingsRow("Launch at login") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { value in
                                LaunchManager.setEnabled(value)
                            }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: hudToastSettings.isEnabled)
                
                // 2. Updates - Standardized per macOSers bundle
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
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .animation(.easeInOut(duration: 0.2), value: autoCheckUpdate)
        .onAppear {
            launchAtLogin = LaunchManager.isEnabled
        }
    }
}

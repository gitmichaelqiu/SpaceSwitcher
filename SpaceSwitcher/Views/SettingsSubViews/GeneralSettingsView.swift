import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var launchAtLogin: Bool = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // 1. General
                SettingsSection("General") {
                    SettingsRow("Launch at Login") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                
                // 2. Updates - Standardized per macOSers bundle
                SettingsSection("Updates") {
                    SettingsRow("Check for Updates Automatically") {
                        Toggle("", isOn: Binding(
                            get: { UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates },
                            set: { UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    if UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates {
                        SettingsRow("Automatically download updates") {
                            Toggle("", isOn: Binding(
                                get: { UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates },
                                set: { UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates = $0 }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                        Divider()
                    }
                    
                    SettingsRow("Check for Updates") {
                        Button("Check Now") {
                            UpdateManager.shared.updaterController.checkForUpdates(nil)
                        }
                    }
                }
                
                // 3. Automation Status
                SettingsSection("Automation API", helperText: "SpaceSwitcher uses the DesktopRenamer API to detect space changes. Ensure the API is enabled in DesktopRenamer.") {
                    SettingsRow("API Status") {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(spaceManager.isAPIEnabled ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(spaceManager.isAPIEnabled ? "Connected" : "Disconnected")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(minHeight: 24)
                    }
                }
                
                // 4. Advanced
                SettingsSection("Advanced") {
                    SettingsRow("Force Rule Refresh") {
                        Button("Refresh Now") {
                            spaceManager.refreshSpaceList()
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

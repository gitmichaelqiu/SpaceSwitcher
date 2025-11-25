import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var renamerClient: RenamerClient
    @State private var launchAtLogin = LaunchManager.isEnabled
    @State private var autoCheckForUpdates = UpdateManager.isAutoCheckEnabled
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("API Connection") {
                    SettingsRow("DesktopRenamer API Status") {
                        HStack {
                            Circle()
                                .fill(renamerClient.availableSpaces.isEmpty ? Color.red : Color.green)
                                .frame(width: 8, height: 8)
                            Text(renamerClient.availableSpaces.isEmpty ? "Not Connected" : "Connected")
                                .foregroundColor(.primary)
                                .padding(4)
                        }
                    }
                    
                    if !renamerClient.availableSpaces.isEmpty {
                        Divider()
                        
                        SettingsRow("Current Space") {
                            Text(renamerClient.currentSpaceName)
                                .foregroundColor(.primary)
                                .padding(4)
                        }
                    }
                    
                    if renamerClient.availableSpaces.isEmpty {
                        Divider()
                        
                        SettingsRow(nil) {
                            Text("Open DesktopRenamer and enable API")
                                .foregroundStyle(.secondary)
                                .padding(4)
                        }
                    }
                }
                
                SettingsSection("Launch") {
                    SettingsRow("Launch At Login") {
                        Toggle("Launch At Login", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { _ in
                                LaunchManager.setEnabled(launchAtLogin)
                            }
                    }
                }
                
                SettingsSection("Settings.General.Update") {
                    SettingsRow("Settings.General.Update.AutoCheck") {
                        Toggle("", isOn: $autoCheckForUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoCheckForUpdates) { _ in
                                UpdateManager.isAutoCheckEnabled = autoCheckForUpdates
                            }
                    }
                    Divider()
                    SettingsRow("Settings.General.Update.ManualCheck") {
                        Button(NSLocalizedString("Settings.General.Update.ManualCheck", comment: "")) {
                            Task {
                                await UpdateManager.shared.checkForUpdate(from: NSApp.keyWindow)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: renamerClient.availableSpaces.isEmpty)
        }
    }
}

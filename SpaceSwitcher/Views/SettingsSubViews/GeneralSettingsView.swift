import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var launchAtLogin: Bool = false
    @State private var autoCheckUpdate: Bool = true
    
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
                        Toggle("", isOn: $autoCheckUpdate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoCheckUpdate) { value in
                                UpdateManager.isAutoCheckEnabled = value
                            }
                    }
                    Divider()
                    SettingsRow("Check for Updates") {
                        Button("Check Now") {
                            Task {
                                await UpdateManager.shared.checkForUpdate(from: nil)
                            }
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
                        .frame(minHeight: 28) // Fixed height to match Toggles/Buttons
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

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var launchAtLogin: Bool = false
    @State private var autoCheckUpdate: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // General Settings
            SettingsSection("General") {
                SettingsRow("Launch at Login") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Divider()
                SettingsRow("Check for Updates Automatically") {
                    Toggle("", isOn: $autoCheckUpdate)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            
            // Automation Status
            SettingsSection("Automation API", helperText: "SpaceSwitcher uses the DesktopRenamer API to detect space changes. Ensure the API is enabled in DesktopRenamer.") {
                SettingsRow("API Status") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(spaceManager.isAPIEnabled ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(spaceManager.isAPIEnabled ? "Connected" : "Disconnected")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // Advanced
            SettingsSection("Advanced") {
                SettingsRow("Force Rule Refresh") {
                    Button("Refresh Now") {
                        spaceManager.refreshSpaceList()
                    }
                }
                Divider()
                SettingsRow("Check for Updates") {
                    Button("Check Now") {
                        // Action
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

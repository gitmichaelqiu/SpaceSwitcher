import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @State private var launchAtLogin = LaunchManager.isEnabled
    @State private var autoCheckForUpdates = UpdateManager.isAutoCheckEnabled
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: - API Connection
            SettingsSection("API Connection") {
                SettingsRow("DesktopRenamer API Status") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(spaceManager.availableSpaces.isEmpty ? Color.red : Color.green)
                            .frame(width: 8, height: 8)
                        Text(spaceManager.availableSpaces.isEmpty ? "Not Connected" : "Connected")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(spaceManager.availableSpaces.isEmpty ? .secondary : .primary)
                    }
                }
                
                if !spaceManager.availableSpaces.isEmpty {
                    Divider().padding(.horizontal, 10).opacity(0.5)
                    
                    SettingsRow("Current Space") {
                        Text(spaceManager.currentSpaceName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                if spaceManager.availableSpaces.isEmpty {
                    Divider().padding(.horizontal, 10).opacity(0.5)
                    
                    SettingsRow("Status") {
                        Text("Open DesktopRenamer and enable API")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // MARK: - Launch
            SettingsSection("Launch") {
                SettingsRow("Launch At Login") {
                    Toggle("Launch At Login", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                        .onChange(of: launchAtLogin) { _ in
                            LaunchManager.setEnabled(launchAtLogin)
                        }
                }
            }
            
            // MARK: - Update
            SettingsSection("Software Update") {
                SettingsRow("Automatically Check") {
                    Toggle("", isOn: $autoCheckForUpdates)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                        .onChange(of: autoCheckForUpdates) { _ in
                            UpdateManager.isAutoCheckEnabled = autoCheckForUpdates
                        }
                }
                
                Divider().padding(.horizontal, 10).opacity(0.5)
                
                SettingsRow("Check for Updates") {
                    Button {
                        Task {
                            await UpdateManager.shared.checkForUpdate(from: NSApp.keyWindow)
                        }
                    } label: {
                        Text("Check Now...")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: spaceManager.availableSpaces.isEmpty)
    }
}

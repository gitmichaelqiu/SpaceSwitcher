import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var renamerClient: RenamerClient
    @State private var launchAtLogin = LaunchManager.isEnabled
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("API Connection") {
                    SettingsRow("Renamer API Status") {
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
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: renamerClient.availableSpaces.isEmpty)
        }
    }
}

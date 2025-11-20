import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var renamerClient: RenamerClient
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                SettingsSection("API Connection") {
                    SettingsRow("Renamer API Status") {
                        HStack {
                            Circle()
                                .fill(renamerClient.availableSpaces.isEmpty ? Color.red : Color.green)
                                .frame(width: 8, height: 8)
                            Text(renamerClient.availableSpaces.isEmpty ? "Not Connected / No Spaces" : "Connected")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Current Space") {
                        Text(renamerClient.currentSpaceName)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                            )
                            .foregroundColor(.primary)
                            .font(.body)
                    }
                }
                
                SettingsSection("Information") {
                    Text("SpaceSwitcher works by listening to DesktopRenamer. Ensure DesktopRenamer is running and the API is enabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

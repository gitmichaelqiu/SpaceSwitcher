import SwiftUI

struct GeneralView: View {
    @ObservedObject var renamerClient: RenamerClient
    
    var body: some View {
        Form {
            SettingsSection("Connection") {
                SettingsRow("Renamer API Status") {
                    HStack {
                        Circle()
                            .fill(renamerClient.availableSpaces.isEmpty ? Color.red : Color.green)
                            .frame(width: 8, height: 8)
                        Text(renamerClient.availableSpaces.isEmpty ? "Not Connected / No Spaces" : "Connected")
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsRow("Current Space") {
                    Text(renamerClient.currentSpaceName)
                        .padding(4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            SettingsSection("Help") {
                Text("SpaceSwitcher works by listening to DesktopRenamer. Ensure DesktopRenamer is running and the API is enabled.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
            }
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "appwindow.swipe.rectangle")
                .font(.system(size: 50))
            Text("SpaceSwitcher")
                .font(.title)
            Text("v1.0.0")
                .foregroundColor(.secondary)
        }
    }
}

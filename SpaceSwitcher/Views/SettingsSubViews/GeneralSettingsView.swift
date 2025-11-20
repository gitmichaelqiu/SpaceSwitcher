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
                            Text(renamerClient.availableSpaces.isEmpty ? "Not Connected" : "Connected")
                                .foregroundColor(.primary)
                                .padding(4)
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Current Space") {
                        Text(renamerClient.currentSpaceName)
                            .padding(4)
                            .foregroundColor(.primary)
                            .font(.body)
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

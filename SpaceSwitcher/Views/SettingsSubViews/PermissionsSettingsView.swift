import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Permissions", helperText: "If the status shows 'Granted' but automation isn't working, try removing SpaceSwitcher from the list in System Settings and re-adding it.") {
                    SettingsRow("Accessibility", helperText: "Required for detecting active applications and space changes via the bundle API.") {
                        HStack(spacing: 8) {
                            if permissionManager.isAccessibilityGranted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            
                            Button(permissionManager.isAccessibilityGranted ? "Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
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

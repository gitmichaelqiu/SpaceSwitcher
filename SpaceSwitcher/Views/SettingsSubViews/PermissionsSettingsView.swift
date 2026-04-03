import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("System Permissions", helperText: "If the status shows 'Granted' but automation isn't working, try removing SpaceSwitcher from the list in System Settings and re-adding it.") {
                SettingsRow("Accessibility") {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(permissionManager.isAccessibilityGranted ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            
                            Text(permissionManager.isAccessibilityGranted ? "Granted" : "Not Granted")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(permissionManager.isAccessibilityGranted ? .primary : .secondary)
                        }
                        
                        Button {
                            permissionManager.requestAccessibilityPermission()
                        } label: {
                            Text(permissionManager.isAccessibilityGranted ? "Open System Settings" : "Grant Access")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            
            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: permissionManager.isAccessibilityGranted)
    }
}

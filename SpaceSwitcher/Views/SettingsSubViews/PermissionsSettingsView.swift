import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @ObservedObject var spaceManager: SpaceManager

    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
    }
    
    var body: some View {
        SettingsContainer(.permissions) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Permissions", helperText: "If the status shows 'Granted' but automation isn't working, try removing SpaceSwitcher from the list in System Settings and re-adding it.") {
                    SettingsRow("Accessibility", helperText: "Required for reading active applications and controlling their visibility in automation rules.") {
                        HStack(spacing: 8) {
                            if permissionManager.hasAccessibilityPermission {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            
                            Button(permissionManager.hasAccessibilityPermission ? "Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
                        }
                    }

                    Divider()

                    SettingsRow("Input Events", helperText: "Required for sending the keyboard shortcuts used by automation rules.") {
                        HStack(spacing: 8) {
                            if permissionManager.isEventSynthesisGranted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }

                            Button(permissionManager.isEventSynthesisGranted ? "Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
                        }
                    }

                    Divider()

                    SettingsRow(
                        "DesktopRenamer SpaceAPI",
                        helperText: "Required for reading desktop spaces and using space-based automation."
                    ) {
                        SpaceAPIStatusView(spaceManager: spaceManager)
                    }
                }
                
                Spacer()
            }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            permissionManager.checkPermissions()
            spaceManager.refreshSpaceList()
        }
        }
    }
}

struct SpaceAPIStatusView: View {
    @ObservedObject var spaceManager: SpaceManager

    var body: some View {
        HStack(spacing: 8) {
            PermissionStatusIcon(isGranted: spaceManager.apiAvailability == .available)

            switch spaceManager.apiAvailability {
            case .available, .disabled:
                Button("Open DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
            case .unavailable:
                Button("Launch DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
                .disabled(spaceManager.desktopRenamerApplicationURL == nil)

                Button("Install DesktopRenamer") {
                    spaceManager.openDesktopRenamerDownloadPage()
                }
            }
        }
        .frame(minHeight: 24)
    }
}

struct PermissionStatusIcon: View {
    let isGranted: Bool

    var body: some View {
        Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(isGranted ? .green : .red)
    }
}

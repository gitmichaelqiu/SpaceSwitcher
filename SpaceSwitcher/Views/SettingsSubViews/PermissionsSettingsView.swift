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
                SettingsSection(
                    "Permissions",
                    helperText: "Accessibility controls both window automation and input events."
                ) {
                    SettingsRow("Accessibility") {
                        HStack(spacing: 8) {
                            PermissionStatusIcon(isGranted: permissionManager.isAccessibilityGranted)

                            Button(permissionManager.isAccessibilityGranted ? "Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
                        }
                    }

                    Divider()

                    SettingsRow("Input Events") {
                        HStack(spacing: 8) {
                            PermissionStatusIcon(isGranted: permissionManager.isEventSynthesisGranted)

                            Button(permissionManager.isEventSynthesisGranted ? "Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
                        }
                    }

                    Divider()

                    SettingsRow(
                        "DesktopRenamer SpaceAPI"
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
            switch spaceManager.apiAvailability {
            case .available:
                PermissionStatusIcon(isGranted: true)
                Button("Open DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
            case .disabled:
                PermissionStatusIcon(isGranted: false)
                Button("Open DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
            case .unavailable:
                PermissionStatusIcon(isGranted: false)
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
            .accessibilityLabel(isGranted ? "Granted" : "Not granted")
    }
}

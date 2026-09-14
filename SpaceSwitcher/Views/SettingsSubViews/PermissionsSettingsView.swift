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
                SettingsSection("Permissions") {
                    SettingsRow("Accessibility") {
                        HStack(spacing: 8) {
                            PermissionStatusView(isGranted: permissionManager.isAccessibilityGranted)

                            Button(permissionManager.isAccessibilityGranted ? "Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
                        }
                    }

                    Divider()

                    SettingsRow("Input Events") {
                        HStack(spacing: 8) {
                            PermissionStatusView(isGranted: permissionManager.isEventSynthesisGranted)

                            Button(permissionManager.isEventSynthesisGranted ? "Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
                        }
                    }

                    Divider()

                }

                SettingsSection(
                    "SpaceAPI",
                    helperText: "SpaceSwitcher uses DesktopRenamer's SpaceAPI to read the current desktop."
                ) {
                    SettingsRow("Status") {
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
                SpaceAPIStatusLabel(title: "Connected", color: .green)
                Button("Open DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
            case .disabled:
                SpaceAPIStatusLabel(title: "Disabled", color: .orange)
                Button("Open DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
            case .unavailable:
                SpaceAPIStatusLabel(title: "Unavailable", color: .red)
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

struct PermissionStatusView: View {
    let isGranted: Bool

    private var statusTitle: LocalizedStringKey {
        isGranted ? "Granted" : "Needs Access"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .red)

            Text(statusTitle)
                .foregroundStyle(.secondary)
        }
    }
}

struct SpaceAPIStatusLabel: View {
    let title: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(color)

            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

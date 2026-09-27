import SwiftUI
import UserNotifications
import Combine
import AppKit
import ServiceManagement

// MARK: - App State
class AppState: ObservableObject {
    dynamic let spaceManager: SpaceManager
    let ruleManager: RuleManager
    let dockManager: DockManager
    
    init() {
        print("APP: Launching Services...")
        self.spaceManager = SpaceManager()
        self.ruleManager = RuleManager()
        self.ruleManager.spaceManager = self.spaceManager
        self.dockManager = DockManager()
        self.dockManager.spaceManager = self.spaceManager
        print("APP: Services Linked and Running.")
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    private lazy var appState = AppState()
    var statusBarManager: StatusBarManager?

    @objc func quitApp() {
        NSApp.terminate(self)
    }

    @objc func openSettingsWindow() {
        SettingsWindowController.shared.open(
            spaceManager: appState.spaceManager,
            ruleManager: appState.ruleManager,
            dockManager: appState.dockManager
        )
    }
    
    @objc func openAboutWindow() {
        SettingsWindowController.shared.open(
            spaceManager: appState.spaceManager,
            ruleManager: appState.ruleManager,
            dockManager: appState.dockManager,
            targetTab: .about
        )
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SpaceSwitcherMigrationFinalizer.shared.startIfRequested() {
            return
        }

        if SpaceSwitcherBridgeMigrationManager.shared.beginIfNeeded(completion: { [weak self] in
            self?.startNormalApplication()
        }) {
            return
        }

        startNormalApplication()
    }

    private func startNormalApplication() {
        NSApp.setActivationPolicy(.accessory)
        SpaceSwitcherIdentityMigration.prepareLegacyBridgeLaunch()
        SpaceSwitcherIdentityMigration.prepareNormalLaunch()
        
        statusBarManager = StatusBarManager(
            appDelegate: self,
            spaceManager: appState.spaceManager,
            ruleManager: appState.ruleManager,
            dockManager: appState.dockManager
        )

        SpaceSwitcherIdentityMigration.completeSuccessfulLaunch()
        
        UNUserNotificationCenter.current().delegate = self
        
        // Start Sparkle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            _ = UpdateManager.shared
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

@main
struct SpaceSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSSplitViewItem.preventSettingsSidebarCollapse()
    }

    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SpaceSwitcher") {
                    appDelegate.openAboutWindow()
                }
            }
            CommandGroup(replacing: .appSettings) { }
        }
    }
}

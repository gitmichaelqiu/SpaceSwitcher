import SwiftUI
import UserNotifications
import Combine
import AppKit

// This class ensures services are running before UI is shown
class AppState: ObservableObject {
    // KVO requires properties to be dynamic/ObjC compatible for observation
    dynamic let renamerClient: RenamerClient // Make dynamic for KVO
    let ruleManager: RuleManager
    
    init() {
        print("APP: Launching Services...")
        self.renamerClient = RenamerClient()
        self.ruleManager = RuleManager()
        self.ruleManager.renamerClient = self.renamerClient
        print("APP: Services Linked and Running.")
    }
}

// Based on OptClicker's AppDelegate for window management
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    let appState = AppState()
    var statusBarManager: StatusBarManager? // New property for the manager

    @objc func quitApp() {
        NSApp.terminate(self)
    }

    @objc func openSettingsWindow() {
        SettingsWindowController.shared.open(
            renamerClient: appState.renamerClient,
            ruleManager: appState.ruleManager
        )
    }
    
    // New function to handle the "About" menu item, matching OptClicker logic
    @objc func openAboutWindow() {
        // Set selected tab to about, then open the window
        UserDefaults.standard.set(SettingsTab.about.rawValue, forKey: "selectedSettingsTab")
        openSettingsWindow()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initially set activation policy to accessory since we are a menubar app
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize the Status Bar Manager here
        statusBarManager = StatusBarManager(
            appDelegate: self,
            renamerClient: appState.renamerClient
        )
        
        UNUserNotificationCenter.current().delegate = self
        if UpdateManager.isAutoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Task {
                    await UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: true)
                }
            }
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        if response.actionIdentifier == "openRelease",
           let url = URL(string: UpdateManager.shared.latestReleaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
            NSWorkspace.shared.open(url)
            NSApp.perform(#selector(NSApp.terminate), with: nil, afterDelay: 0.5)
        }
    }
}


@main
struct SpaceSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // 1. Remove MenuBarExtra completely. The StatusBarManager handles the menu bar item.
        
        // 2. Keep Settings and Commands for standard macOS menu support
        Settings { EmptyView() }
        .commands {
            // OptClicker's command structure
            CommandGroup(replacing: .appInfo) {
                // Route to the new openAboutWindow
                Button("About SpaceSwitcher") {
                    appDelegate.openAboutWindow()
                }
            }
            CommandGroup(replacing: .appSettings) { } // Empty to hide Settings menu item
        }
    }
}

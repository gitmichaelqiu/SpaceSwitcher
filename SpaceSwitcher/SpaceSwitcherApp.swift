import SwiftUI
import Combine
import AppKit

// This class ensures services are running before UI is shown
class AppState: ObservableObject {
    let renamerClient: RenamerClient
    let ruleEngine: RuleEngine
    
    init() {
        print("APP: Launching Services...")
        // 1. Create services
        self.renamerClient = RenamerClient()
        self.ruleEngine = RuleEngine()
        
        // 2. Wire them together immediately
        self.ruleEngine.renamerClient = self.renamerClient
        
        print("APP: Services Linked and Running.")
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // AppState is created here, as dependencies are needed for the window controller
    let appState = AppState()
    
    @objc func quitApp() {
        NSApp.terminate(self)
    }

    // Function to open the settings window using the controller
    @objc func openSettingsWindow() {
        SettingsWindowController.shared.open(
            renamerClient: appState.renamerClient,
            ruleEngine: appState.ruleEngine
        )
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initially set activation policy to accessory since we are a menubar app
        NSApp.setActivationPolicy(.accessory)
    }
}


@main
struct SpaceSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            // Update the settings button action to use the new AppDelegate function
            Button("Settings...") {
                appDelegate.openSettingsWindow()
            }
            Divider()
            Button("Quit SpaceSwitcher") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            // Replaced default icon to a cleaner system icon
            Image(systemName: "rectangle.split.2x1")
        }
        
        // Settings scene is replaced with an empty one, as the window is managed by the controller
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SpaceSwitcher") {
                    // Set selected tab to about, then open the window
                    UserDefaults.standard.set(SettingsTab.about.rawValue, forKey: "selectedSettingsTab")
                    appDelegate.openSettingsWindow()
                }
            }
            CommandGroup(replacing: .appSettings) { } // Empty to hide Settings menu item
        }
    }
}

// The old extension NSApplication.showSettingsWindow() is no longer needed

import SwiftUI
import Combine
import AppKit

// This class ensures services are running before UI is shown
class AppState: ObservableObject {
    let renamerClient: RenamerClient
    let ruleEngine: RuleEngine
    
    init() {
        print("APP: Launching Services...")
        
        self.renamerClient = RenamerClient()
        self.ruleEngine = RuleEngine()
        
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
            Button("Settings...") {
                appDelegate.openSettingsWindow()
            }
            Divider()
            Button("Quit SpaceSwitcher") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "appwindow.swipe.rectangle")
        }
        
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SpaceSwitcher") {
                    UserDefaults.standard.set(SettingsTab.about.rawValue, forKey: "selectedSettingsTab")
                    appDelegate.openSettingsWindow()
                }
            }
            CommandGroup(replacing: .appSettings) { }
        }
    }
}

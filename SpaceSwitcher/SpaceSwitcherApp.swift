import SwiftUI
import Combine

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

@main
struct SpaceSwitcherApp: App {
    // Initialize AppState once on launch
    @StateObject var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            Button("Settings...") {
                NSApp.sendAction(#selector(NSApplication.showSettingsWindow), to: nil, from: nil)
            }
            Divider()
            Button("Quit SpaceSwitcher") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "appwindow.swipe.rectangle")
        }
        
        Settings {
            // Pass the pre-initialized objects to the view
            SettingsView(renamerClient: appState.renamerClient, ruleEngine: appState.ruleEngine)
        }
    }
}

extension NSApplication {
    @objc func showSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

import SwiftUI

@main
struct SpaceSwitcherApp: App {
    @StateObject var renamerClient = RenamerClient()
    @StateObject var ruleEngine = RuleEngine()
    
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
            SettingsView(renamerClient: renamerClient, ruleEngine: ruleEngine)
                .onAppear {
                    // Connect the engine to the client
                    ruleEngine.renamerClient = renamerClient
                    // Start listening
                    renamerClient.startListening()
                }
        }
    }
}

extension NSApplication {
    @objc func showSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

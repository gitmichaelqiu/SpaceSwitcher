import SwiftUI
import UserNotifications
import Combine
import AppKit
import ServiceManagement

// MARK: - Sidebar Fix
extension NSSplitViewItem {
    @nonobjc private static let swizzler: () = {
        let originalSelector = #selector(getter: canCollapse)
        let swizzledSelector = #selector(getter: swizzledCanCollapse)

        guard
            let originalMethod = class_getInstanceMethod(NSSplitViewItem.self, originalSelector),
            let swizzledMethod = class_getInstanceMethod(NSSplitViewItem.self, swizzledSelector)
        else { return }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc private var swizzledCanCollapse: Bool {
        // If this split view item belongs to our specific Settings Window, return false
        if let window = viewController.view.window,
           window.identifier?.rawValue == "SettingsWindow" {
            return false
        }
        return self.swizzledCanCollapse
    }

    static func swizzle() {
        _ = swizzler
    }
}

@available(macOS 14.0, *)
extension View {
    func removeSidebarToggle() -> some View {
        toolbar(removing: .sidebarToggle)
            .toolbar { Color.clear }
    }
}

// MARK: - App State
class AppState: ObservableObject {
    dynamic let spaceManager: SpaceManager
    let ruleManager: RuleManager
    
    init() {
        print("APP: Launching Services...")
        self.spaceManager = SpaceManager()
        self.ruleManager = RuleManager()
        self.ruleManager.spaceManager = self.spaceManager
        print("APP: Services Linked and Running.")
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    let appState = AppState()
    var statusBarManager: StatusBarManager?

    @objc func quitApp() {
        NSApp.terminate(self)
    }

    @objc func openSettingsWindow() {
        SettingsWindowController.shared.open(
            spaceManager: appState.spaceManager,
            ruleManager: appState.ruleManager
        )
    }
    
    @objc func openAboutWindow() {
        // Pre-select About tab if desired, though NavigationSplitView handles state differently
        // We can handle this via a notification or singleton state if strictly needed,
        // but opening the window is the primary action.
        SettingsWindowController.shared.open(
            spaceManager: appState.spaceManager,
            ruleManager: appState.ruleManager,
            targetTab: .about
        )
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusBarManager = StatusBarManager(
            appDelegate: self,
            spaceManager: appState.spaceManager
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
    
    init() {
        NSSplitViewItem.swizzle()
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

import SwiftUI
import AppKit

let defaultSettingsWindowWidth = 450
let defaultSettingsWindowHeight = 480

class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var renamerClient: RenamerClient?
    private var ruleManager: RuleManager?
    
    private override init() {
        super.init()
    }

    func open(renamerClient: RenamerClient, ruleManager: RuleManager) {
        self.renamerClient = renamerClient
        self.ruleManager = ruleManager

        if window == nil {
            createWindow()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func createWindow() {
        let size = NSSize(width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.center()
        win.setFrameAutosaveName("Settings")
        win.isReleasedWhenClosed = false
        win.minSize = size
        win.maxSize = size
        win.level = .normal
        win.collectionBehavior = [.participatesInCycle]

        // Inject dependencies
        guard let renamerClient = self.renamerClient,
              let ruleManager = self.ruleManager else {
            fatalError("SettingsWindowController: dependencies not set")
        }

        let rootView = SettingsView(renamerClient: renamerClient, ruleManager: ruleManager)
        win.contentView = NSHostingView(rootView: rootView)

        // Observe close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: win
        )

        self.window = win
    }
}

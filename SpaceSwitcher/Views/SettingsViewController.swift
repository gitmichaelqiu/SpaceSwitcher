import SwiftUI
import AppKit

// Matching OptClicker's window size
let defaultSettingsWindowWidth = 450
let defaultSettingsWindowHeight = 480

class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var renamerClient: RenamerClient?
    private var ruleEngine: RuleEngine?
    
    private override init() {
        super.init()
    }

    func open(renamerClient: RenamerClient, ruleEngine: RuleEngine) {
        self.renamerClient = renamerClient
        self.ruleEngine = ruleEngine

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
        win.maxSize = size // Fixed size to match OptClicker
        win.level = .normal
        win.collectionBehavior = [.participatesInCycle]

        // Inject dependencies
        guard let renamerClient = self.renamerClient,
              let ruleEngine = self.ruleEngine else {
            fatalError("SettingsWindowController: dependencies not set")
        }

        let rootView = SettingsView(renamerClient: renamerClient, ruleEngine: ruleEngine)
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

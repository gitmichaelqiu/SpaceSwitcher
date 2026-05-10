import SwiftUI
import AppKit

class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var windowController: NSWindowController?
    
    // UPDATED: Hold a weak reference to RuleManager to trigger updates on close
    private weak var ruleManager: RuleManager?
    
    private override init() {
        super.init()
    }

    func open(spaceManager: SpaceManager, ruleManager: RuleManager, dockManager: DockManager, targetTab: SettingsTab? = nil) {
        NSApp.setActivationPolicy(.regular)

        // UPDATED: Store reference
        self.ruleManager = ruleManager

        // If window exists, just bring to front (and optionally switch tab if we implemented binding update logic)
        if let win = self.window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        createWindow(spaceManager: spaceManager, ruleManager: ruleManager, dockManager: dockManager, startTab: targetTab)
    }

    private func createWindow(spaceManager: SpaceManager, ruleManager: RuleManager, dockManager: DockManager, startTab: SettingsTab?) {
        // 1. STYLE: .fullSizeContentView is critical for the "Ice" style (content goes behind title bar)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        win.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        
        // 2. CONFIG: Hide the native title bar elements
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        
        // 3. REMOVE TOOLBAR: Ensures no extra space is reserved at the top
        win.toolbar = nil
        
        win.center()
        win.setFrameAutosaveName("Settings")
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
        win.collectionBehavior = [.participatesInCycle]
        win.level = .normal
        
        // 4. CONTENT: Use the custom HostingController
        let settingsVC = SettingsHostingController(
            spaceManager: spaceManager,
            ruleManager: ruleManager,
            dockManager: dockManager,
            startTab: startTab
        )
        win.contentViewController = settingsVC

        // 5. WINDOW CONTROLLER
        let wc = NSWindowController(window: win)
        wc.window?.delegate = self
        self.windowController = wc
        self.window = win
        
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Switch back to accessory (menu bar only) mode when settings close
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            // UPDATED: Force rule refresh when settings window closes
            self.ruleManager?.forceRefresh()
        }
        self.window = nil
        self.windowController = nil
    }
}

import Foundation
import AppKit
import Combine // Import Combine

class StatusBarManager: NSObject {
    private var statusBarItem: NSStatusItem!
    private weak var appDelegate: AppDelegate?
    
    // SpaceSwitcher specific dependencies
    private var renamerClient: RenamerClient?
    // Store the Combine subscription to keep it active
    private var connectionCancellable: AnyCancellable?

    init(appDelegate: AppDelegate, renamerClient: RenamerClient) {
        self.appDelegate = appDelegate
        self.renamerClient = renamerClient
        super.init()
        
        setupStatusBar()
        // Use Combine observation
        setupCombineObservation()
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusBarItem.button {
            button.image = NSImage(named: "StatusIcon")
            updateStatusToolTip(isConnected: renamerClient?.availableSpaces.isEmpty == false)
        }

        statusBarItem.menu = createMenu()
    }
    
    private func setupCombineObservation() {
        // FIX: Use Combine to monitor changes to the @Published property
        connectionCancellable = renamerClient?.$availableSpaces
            .receive(on: DispatchQueue.main) // Ensure updates are on the main thread
            .sink { [weak self] spaces in
                // Check if availableSpaces array is non-empty to determine connection status
                let isConnected = !spaces.isEmpty
                self?.updateStatusToolTip(isConnected: isConnected)
            }
    }
    
    private func updateStatusToolTip(isConnected: Bool) {
        let status = isConnected ? "Connected" : "Disconnected"
        statusBarItem.button?.toolTip = "SpaceSwitcher: \(status)"
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: NSLocalizedString("Settings", comment: ""),
                                      action: #selector(AppDelegate.openSettingsWindow),
                                      keyEquivalent: ",")
        settingsItem.target = appDelegate
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: NSLocalizedString("Quit", comment: ""),
                                  action: #selector(AppDelegate.quitApp),
                                  keyEquivalent: "q")
        quitItem.target = appDelegate
        menu.addItem(quitItem)
        
        return menu
    }
    
    deinit {
        connectionCancellable?.cancel()
    }
}

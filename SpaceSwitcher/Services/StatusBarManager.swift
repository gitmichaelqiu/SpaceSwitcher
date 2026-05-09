import Foundation
import AppKit
import Combine // Import Combine

class StatusBarManager: NSObject {
    private var statusBarItem: NSStatusItem!
    private weak var appDelegate: AppDelegate?
    
    // SpaceSwitcher specific dependencies
    private var spaceManager: SpaceManager?
    private var ruleManager: RuleManager?
    private var dockManager: DockManager?
    
    // Store Combine subscriptions to keep them active
    private var cancellables = Set<AnyCancellable>()

    init(appDelegate: AppDelegate, spaceManager: SpaceManager, ruleManager: RuleManager, dockManager: DockManager) {
        self.appDelegate = appDelegate
        self.spaceManager = spaceManager
        self.ruleManager = ruleManager
        self.dockManager = dockManager
        super.init()
        
        setupStatusBar()
        // Use Combine observation
        setupCombineObservation()
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusBarItem.button {
            button.image = NSImage(named: "StatusIcon")
            updateStatusToolTip(isConnected: spaceManager?.availableSpaces.isEmpty == false)
        }

        statusBarItem.menu = createMenu()
    }
    
    private func setupCombineObservation() {
        // Monitor connection status
        spaceManager?.$availableSpaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spaces in
                self?.updateStatusToolTip(isConnected: !spaces.isEmpty)
            }
            .store(in: &cancellables)
            
        // Monitor Rule automation status to update menu
        ruleManager?.$isAutomationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
            
        // Monitor Dock automation status to update menu
        dockManager?.config.$isAutomationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
    }
    
    private func updateMenu() {
        statusBarItem.menu = createMenu()
    }
    
    private func updateStatusToolTip(isConnected: Bool) {
        let status = isConnected ? "Connected" : "Disconnected"
        statusBarItem.button?.toolTip = "SpaceSwitcher: \(status)"
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        // 1. Settings
        let settingsItem = NSMenuItem(title: NSLocalizedString("Settings", comment: ""),
                                      action: #selector(AppDelegate.openSettingsWindow),
                                      keyEquivalent: ",")
        settingsItem.target = appDelegate
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        
        // 2. Automation Toggles
        let rulesItem = NSMenuItem(title: NSLocalizedString("Automated rules", comment: ""),
                                   action: #selector(toggleRules),
                                   keyEquivalent: "")
        rulesItem.target = self
        rulesItem.state = (ruleManager?.isAutomationEnabled ?? false) ? .on : .off
        menu.addItem(rulesItem)
        
        let docksItem = NSMenuItem(title: NSLocalizedString("Automated docks", comment: ""),
                                   action: #selector(toggleDocks),
                                   keyEquivalent: "")
        docksItem.target = self
        docksItem.state = (dockManager?.config.isAutomationEnabled ?? false) ? .on : .off
        menu.addItem(docksItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Quit
        let quitItem = NSMenuItem(title: NSLocalizedString("Quit", comment: ""),
                                  action: #selector(AppDelegate.quitApp),
                                  keyEquivalent: "q")
        quitItem.target = appDelegate
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func toggleRules() {
        guard let rm = ruleManager else { return }
        rm.isAutomationEnabled.toggle()
    }
    
    @objc private func toggleDocks() {
        guard let dm = dockManager else { return }
        dm.config.isAutomationEnabled.toggle()
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}

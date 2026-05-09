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
            .sink { [weak self] (isEnabled: Bool) in self?.updateMenu() }
            .store(in: &cancellables)
            
        // Monitor Dock configuration changes (Automation status, Dock Sets, etc.)
        dockManager?.$config
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
            
        // Monitor Active Dock Set to update checkmarks in manual list
        dockManager?.$activeDockSetID
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

        let rulesItem = NSMenuItem(title: NSLocalizedString("Rule Automation", comment: ""),
                            action: #selector(toggleRules),
                            keyEquivalent: "")
        rulesItem.target = self
        rulesItem.state = (ruleManager?.isAutomationEnabled ?? false) ? .on : .off
        rulesItem.image = NSImage(systemSymbolName: "list.bullet.below.rectangle", accessibilityDescription: nil)
        menu.addItem(rulesItem)
        
        let docksItem = NSMenuItem(title: NSLocalizedString("Dock Automation", comment: ""),
                                   action: #selector(toggleDocks),
                                   keyEquivalent: "")
        docksItem.target = self
        docksItem.state = (dockManager?.config.isAutomationEnabled ?? false) ? .on : .off
        docksItem.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: nil)
        menu.addItem(docksItem)

        // 2.1 Manual Dock Switching (if automation is disabled)
        if let dm = dockManager, !dm.config.isAutomationEnabled {
            menu.addItem(NSMenuItem.separator())
            
            for set in dm.config.dockSets {
                let setItem = NSMenuItem(title: set.name,
                                         action: #selector(switchDockSet(_:)),
                                         keyEquivalent: "")
                setItem.target = self
                setItem.representedObject = set.id
                setItem.state = (dm.activeDockSetID == set.id) ? .on : .off
                // Add a small dock icon to each set item
                setItem.image = NSImage(systemSymbolName: "square.grid.3x1.below.line.grid.1x2", accessibilityDescription: nil)
                menu.addItem(setItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: NSLocalizedString("Settings", comment: ""),
                                      action: #selector(AppDelegate.openSettingsWindow),
                                      keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.target = appDelegate
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: NSLocalizedString("Quit", comment: ""),
                                  action: #selector(AppDelegate.quitApp),
                                  keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.rectangle", accessibilityDescription: nil)
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
    
    @objc private func switchDockSet(_ sender: NSMenuItem) {
        guard let setID = sender.representedObject as? UUID,
              let dm = dockManager else { return }
        
        // Manually apply the selected dock set
        dm.applyDockSetByID(setID)
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}

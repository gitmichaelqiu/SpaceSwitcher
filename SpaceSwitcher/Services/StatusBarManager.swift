import Foundation
import AppKit
import Combine // Import Combine

@MainActor
final class MenuBarIconSettings: ObservableObject {
    static let hideMenuBarIconKey = "hideMenuBarIcon"
    static let shared = MenuBarIconSettings()

    @Published var isHidden: Bool {
        didSet {
            defaults.set(isHidden, forKey: Self.hideMenuBarIconKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isHidden = defaults.bool(forKey: Self.hideMenuBarIconKey)
    }
}

class StatusBarManager: NSObject {
    private var statusBarItem: NSStatusItem!
    private weak var appDelegate: AppDelegate?
    private let menuBarIconSettings = MenuBarIconSettings.shared
    
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
        statusBarItem.isVisible = !menuBarIconSettings.isHidden

        if let button = statusBarItem.button {
            button.image = NSImage(named: "StatusIcon")
            updateStatusToolTip(isConnected: spaceManager?.availableSpaces.isEmpty == false)
        }

        statusBarItem.menu = createMenu()
    }
    
    private func setupCombineObservation() {
        menuBarIconSettings.$isHidden
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isHidden in
                self?.statusBarItem.isVisible = !isHidden
            }
            .store(in: &cancellables)

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

        let rulesItem = NSMenuItem(title: NSLocalizedString("Rule automation", comment: ""),
                            action: #selector(toggleRules),
                            keyEquivalent: "")
        rulesItem.target = self
        rulesItem.state = (ruleManager?.isAutomationEnabled ?? false) ? .on : .off
        rulesItem.image = NSImage(systemSymbolName: "list.bullet.below.rectangle", accessibilityDescription: nil)
        menu.addItem(rulesItem)
        
        let docksItem = NSMenuItem(title: NSLocalizedString("Dock automation", comment: ""),
                                   action: #selector(toggleDocks),
                                   keyEquivalent: "")
        docksItem.target = self
        docksItem.state = (dockManager?.config.isAutomationEnabled ?? false) ? .on : .off
        docksItem.image = NSImage(systemSymbolName: "dock.arrow.up.rectangle", accessibilityDescription: nil)
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
                setItem.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: nil)
                menu.addItem(setItem)
            }
        }

        #if DEBUG
        let debugItem = NSMenuItem(
            title: NSLocalizedString("Debug", comment: "Debug-only menu"),
            action: nil,
            keyEquivalent: ""
        )
        let debugMenu = NSMenu()
        let showHUDItem = NSMenuItem(
            title: NSLocalizedString(
                "Show HUD with multiple actions",
                comment: "Debug-only HUD preview"
            ),
            action: #selector(showHUDWithMultipleActions),
            keyEquivalent: ""
        )
        showHUDItem.target = self
        debugMenu.addItem(showHUDItem)
        debugItem.submenu = debugMenu
        menu.addItem(debugItem)
        #endif

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

    #if DEBUG
    @objc private func showHUDWithMultipleActions() {
        let hiddenSummary = String(
            format: NSLocalizedString("%d hidden", comment: "HUD count of apps hidden"),
            2
        )
        let restoredSummary = String(
            format: NSLocalizedString("%d restored", comment: "HUD count of apps restored"),
            1
        )
        let detailFormat = NSLocalizedString(
            "%@: %@",
            comment: "HUD detail with application and confirmed outcome"
        )
        let detailLines = [
            String(
                format: detailFormat,
                "Music",
                NSLocalizedString("window hidden", comment: "HUD outcome")
            ),
            String(
                format: detailFormat,
                "Mail",
                NSLocalizedString("2 windows hidden", comment: "HUD outcome")
            ),
            String(
                format: detailFormat,
                "Calendar",
                NSLocalizedString("window restored", comment: "HUD outcome")
            )
        ]

        HUDWindowController.shared.show(
            message: [hiddenSummary, restoredSummary].joined(separator: ", "),
            style: .info,
            appIcon: NSApp.applicationIconImage,
            autoHide: false,
            detailLines: detailLines
        )
    }
    #endif
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}

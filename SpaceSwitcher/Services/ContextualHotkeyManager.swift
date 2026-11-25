import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

final class ContextualHotkeyManager: ObservableObject {
    @Published var hotkeys: [ContextualHotkey] {
        didSet {
            persistHotkeys()
            refreshRegistrations()
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            refreshRegistrations()
        }
    }

    @Published private(set) var unavailableShortcutIDs = Set<UUID>()

    weak var spaceManager: SpaceManager?

    private var cancellables = Set<AnyCancellable>()
    private static let hotkeysKey = "SpaceSwitcherContextualHotkeys"
    private static let enabledKey = "SpaceSwitcherContextualHotkeysEnabled"
    private static let hotKeySignature: OSType = 0x5350484B // SPHK

    private let defaults: UserDefaults
    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [EventHotKeyRef] = []
    private var hotKeyIDs: [UInt32: UUID] = [:]

    init(spaceManager: SpaceManager, defaults: UserDefaults = .standard) {
        self.spaceManager = spaceManager
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.hotkeysKey),
           let savedHotkeys = try? JSONDecoder().decode([ContextualHotkey].self, from: data) {
            hotkeys = savedHotkeys
        } else {
            hotkeys = []
        }
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true

        setupSpaceBindings()
        installEventHandler()
        refreshRegistrations()
    }

    deinit {
        unregisterAllHotKeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func add(_ hotkey: ContextualHotkey) {
        hotkeys.append(hotkey)
    }

    @discardableResult
    func moveHotkey(sourceID: String, before targetID: String) -> Bool {
        guard let sourceUUID = UUID(uuidString: sourceID),
              let targetUUID = UUID(uuidString: targetID),
              sourceUUID != targetUUID,
              let sourceIndex = hotkeys.firstIndex(where: { $0.id == sourceUUID }),
              hotkeys.contains(where: { $0.id == targetUUID }) else {
            return false
        }

        var reordered = hotkeys
        let movedHotkey = reordered.remove(at: sourceIndex)
        guard let targetIndex = reordered.firstIndex(where: { $0.id == targetUUID }) else { return false }
        reordered.insert(movedHotkey, at: targetIndex)
        hotkeys = reordered
        return true
    }

    @discardableResult
    func moveHotkeyToEnd(sourceID: String) -> Bool {
        guard let sourceUUID = UUID(uuidString: sourceID),
              let sourceIndex = hotkeys.firstIndex(where: { $0.id == sourceUUID }),
              sourceIndex < hotkeys.count - 1 else {
            return false
        }

        var reordered = hotkeys
        reordered.append(reordered.remove(at: sourceIndex))
        hotkeys = reordered
        return true
    }

    func update(_ hotkey: ContextualHotkey) {
        guard let index = hotkeys.firstIndex(where: { $0.id == hotkey.id }) else { return }
        hotkeys[index] = hotkey
    }

    func delete(_ hotkey: ContextualHotkey) {
        hotkeys.removeAll { $0.id == hotkey.id }
    }

    func duplicate(_ hotkey: ContextualHotkey) -> ContextualHotkey {
        var copy = hotkey.duplicate()
        var candidateName = copy.name
        var suffix = 2
        while hotkeys.contains(where: { $0.name == candidateName }) {
            candidateName = String(
                format: NSLocalizedString("%@ %d", comment: "Suffix for a duplicate contextual hotkey name"),
                copy.name,
                suffix
            )
            suffix += 1
        }
        copy.name = candidateName
        return copy
    }

    func newHotkey(currentSpaceID: String?, availableSpaces: [SpaceInfo]) -> ContextualHotkey {
        let spaceActionGroups: [ContextualHotkeySpaceActionGroup]
        if let currentSpaceID,
           availableSpaces.contains(where: { $0.id == currentSpaceID }) {
            spaceActionGroups = [
                ContextualHotkeySpaceActionGroup(spaceIDs: [currentSpaceID], action: .doNothing)
            ]
        } else {
            spaceActionGroups = []
        }
        return ContextualHotkey(isEnabled: false, spaceActionGroups: spaceActionGroups)
    }

    private func persistHotkeys() {
        guard let data = try? JSONEncoder().encode(hotkeys) else { return }
        defaults.set(data, forKey: Self.hotkeysKey)
    }

    private func setupSpaceBindings() {
        spaceManager?.$availableSpaces
            .sink { [weak self] spaces in
                self?.migrateManagedSpaceReferences(using: spaces)
            }
            .store(in: &cancellables)
    }

    private func migrateManagedSpaceReferences(using spaces: [SpaceInfo]) {
        var managedToStableIDs: [String: String] = [:]
        for space in spaces {
            if let managedSpaceID = space.managedSpaceID, managedSpaceID != space.id {
                managedToStableIDs[managedSpaceID] = space.id
            }
        }
        guard !managedToStableIDs.isEmpty else { return }

        var updatedHotkeys = hotkeys
        var didUpdate = false
        for hotkeyIndex in updatedHotkeys.indices {
            for groupIndex in updatedHotkeys[hotkeyIndex].spaceActionGroups.indices {
                let originalIDs = updatedHotkeys[hotkeyIndex].spaceActionGroups[groupIndex].spaceIDs
                let stableIDs = Set(originalIDs.map { managedToStableIDs[$0] ?? $0 })
                guard stableIDs != originalIDs else { continue }
                updatedHotkeys[hotkeyIndex].spaceActionGroups[groupIndex].spaceIDs = stableIDs
                didUpdate = true
            }
        }

        if didUpdate {
            hotkeys = updatedHotkeys
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else { return }
        eventHandler = handler
    }

    private func refreshRegistrations() {
        unregisterAllHotKeys()
        unavailableShortcutIDs.removeAll()
        guard isEnabled else { return }
        guard eventHandler != nil else {
            unavailableShortcutIDs = Set(
                hotkeys.filter { $0.isEnabled && $0.keyCode != nil }.map(\.id)
            )
            return
        }

        var nextID: UInt32 = 1
        for hotkey in hotkeys where hotkey.isEnabled {
            guard let keyCode = hotkey.keyCode else { continue }
            guard ContextualHotkeyModifiers.containsModifier(hotkey.modifiers),
                  let carbonKeyCode = UInt32(exactly: keyCode) else {
                unavailableShortcutIDs.insert(hotkey.id)
                continue
            }

            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: nextID)
            var hotKeyReference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                carbonKeyCode,
                ContextualHotkeyModifiers.carbonFlags(from: hotkey.modifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                OptionBits(kEventHotKeyNoOptions),
                &hotKeyReference
            )

            guard status == noErr, let hotKeyReference else {
                unavailableShortcutIDs.insert(hotkey.id)
                continue
            }

            registeredHotKeys.append(hotKeyReference)
            hotKeyIDs[nextID] = hotkey.id
            nextID += 1
        }
    }

    private func unregisterAllHotKeys() {
        for hotKey in registeredHotKeys {
            UnregisterEventHotKey(hotKey)
        }
        registeredHotKeys.removeAll()
        hotKeyIDs.removeAll()
    }

    private func handleEventHotKey(identifier: UInt32) {
        guard isEnabled,
              let hotkeyID = hotKeyIDs[identifier],
              let hotkey = hotkeys.first(where: { $0.id == hotkeyID }),
              let spaceManager else {
            return
        }

        let action = ContextualHotkeySpaceResolver.action(
            for: hotkey,
            currentSpaceID: spaceManager.currentSpaceID,
            knownSpaceIDs: Set(spaceManager.availableSpaces.map(\.id)),
            apiIsAvailable: spaceManager.apiAvailability == .available,
            hotkeysAreEnabled: isEnabled
        )
        guard let action,
              let bundleIdentifier = action.appBundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return
        }

        let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first

        switch action.kind {
        case .doNothing:
            return
        case .activateIfRunning:
            runningApplication?.activate(options: [.activateAllWindows])
        case .openOrActivate:
            if let runningApplication {
                runningApplication.activate(options: [.activateAllWindows])
            } else if let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(
                    at: applicationURL,
                    configuration: configuration,
                    completionHandler: nil
                )
            }
        case .hideApp:
            _ = runningApplication?.hide()
        case .unhideApp:
            _ = runningApplication?.unhide()
        case .toggleAppVisibility:
            guard let runningApplication else { return }
            if runningApplication.isHidden {
                _ = runningApplication.unhide()
            } else {
                _ = runningApplication.hide()
            }
        case .minimizeWindows:
            guard let runningApplication else { return }
            setMinimized(true, for: runningApplication)
        case .unminimizeWindows:
            guard let runningApplication else { return }
            setMinimized(false, for: runningApplication)
        case .toggleWindowMinimization:
            guard let runningApplication else { return }
            toggleWindowMinimization(for: runningApplication)
        }
    }

    private func setMinimized(_ isMinimized: Bool, for application: NSRunningApplication) {
        let windows = WindowSpaceService.windows(for: application)
        for window in windows {
            guard WindowSpaceService.isMinimized(window) != isMinimized else { continue }
            _ = WindowSpaceService.setMinimized(window, isMinimized: isMinimized)
        }
    }

    private func toggleWindowMinimization(for application: NSRunningApplication) {
        let windows = WindowSpaceService.windows(for: application)
        guard !windows.isEmpty else { return }

        let shouldMinimize = !windows.allSatisfy { WindowSpaceService.isMinimized($0) == true }
        for window in windows {
            _ = WindowSpaceService.setMinimized(window, isMinimized: shouldMinimize)
        }
    }

    private static let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventParameterNotFoundErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        let manager = Unmanaged<ContextualHotkeyManager>
            .fromOpaque(userData)
            .takeUnretainedValue()
        let identifier = hotKeyID.id
        DispatchQueue.main.async {
            manager.handleEventHotKey(identifier: identifier)
        }
        return noErr
    }
}

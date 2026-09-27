import Foundation
import AppKit
import Sparkle

extension NSApplication {
    // Resolves the most appropriate window for presenting sheet-modal interfaces.
    var suitableSheetWindow: NSWindow? {
        suitableSheetWindow(nil)
    }

    func suitableSheetWindow(_ preferred: NSWindow?) -> NSWindow? {
        if let w = preferred, w.isVisible { return w }

        return keyWindow
            ?? mainWindow
            ?? windows.first { $0.isVisible && $0.isKeyWindow }
            ?? windows.first { $0.isVisible }
            ?? windows.first
    }
}

class UpdateManager: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = UpdateManager()
    
    private(set) var updaterController: SPUStandardUpdaterController!
    
    private override init() {
        super.init()
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        guard SpaceSwitcherBundleIdentity.isCurrentApplication else { return [] }
        return [SpaceSwitcherBundleIdentity.currentUpdateChannel]
    }

    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return SUAppcastItem.empty()
        }

        let eligibleItems = appcast.items.filter { item in
            item.propertiesDictionary[SpaceSwitcherBundleIdentity.appcastTargetBundleIdentifierKey]
                as? String == bundleIdentifier
        }
        guard !eligibleItems.isEmpty else { return SUAppcastItem.empty() }

        let comparator = SUStandardVersionComparator.default
        return eligibleItems.max { left, right in
            comparator.compareVersion(left.versionString, toVersion: right.versionString)
                == .orderedAscending
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }
}

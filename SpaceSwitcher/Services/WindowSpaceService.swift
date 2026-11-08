import AppKit
import ApplicationServices
import CoreGraphics

@_silgen_name("_CGSDefaultConnection")
private func spaceSwitcherDefaultConnection() -> Int32

@_silgen_name("_AXUIElementGetWindow")
private func spaceSwitcherWindowID(
    _ element: AXUIElement,
    _ windowID: inout CGWindowID
) -> Int32

@_silgen_name("CGSCopySpacesForWindows")
private func spaceSwitcherCopySpacesForWindows(
    _ connection: Int32,
    _ mask: Int32,
    _ windows: CFArray
) -> CFArray?

/// Accessibility-backed window targets with their WindowServer space memberships.
/// The WindowServer call is the same source used by DesktopRenamer's SpaceAPI.
struct RuleWindowTarget {
    let id: Int
    let applicationPID: Int32
    let accessibilityElement: AXUIElement
    let spaceIDs: Set<String>
    /// WindowServer's first reported membership. This is a live fallback for
    /// source matching; RuleManager's remembered hide source takes precedence.
    let primarySpaceID: String?
    let isMinimized: Bool?
    let isHidden: Bool?
    let isFullscreen: Bool?
    let isFrontmost: Bool
}

nonisolated struct DockRestartWindowStateSnapshot {
    nonisolated static let accessibilityScanBudget: TimeInterval = 1.0

    struct Application {
        struct Window {
            let wasHidden: Bool
            let wasMinimized: Bool
            let accessibilityElement: AXUIElement
        }

        let processIdentifier: pid_t
        let wasHidden: Bool
        let windows: [Window]
    }

    let accessibilityAvailable: Bool
    let applications: [Application]
    let failedApplicationQueries: Int
    let accessibilityBudgetExhausted: Bool

    nonisolated var minimizedWindowCount: Int {
        applications.reduce(0) { count, application in
            count + application.windows.filter(\.wasMinimized).count
        }
    }

    nonisolated var hiddenWindowCount: Int {
        applications.reduce(0) { count, application in
            count + application.windows.filter(\.wasHidden).count
        }
    }
}

nonisolated struct DockRestartWindowStateRestoreResult {
    var applicationsRehidden = 0
    var windowsRehidden = 0
    var windowsReminimized = 0
    var failedRestorations = 0
    var accessibilityBudgetExhausted = false
}

enum WindowSpaceService {
    static func windows(for application: NSRunningApplication) -> [RuleWindowTarget] {
        guard isAccessibilityTrusted else { return [] }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var windowsReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &windowsReference
        ) == .success,
        let windows = windowsReference as? [AXUIElement] else {
            return []
        }

        let focusedWindowID = focusedWindowID()
        return windows.compactMap { window in
            var windowID: CGWindowID = 0
            guard spaceSwitcherWindowID(window, &windowID) == 0, windowID != 0 else {
                return nil
            }

            let managedSpaceIDs = orderedCurrentSpaceIDs(for: Int(windowID))
            return RuleWindowTarget(
                id: Int(windowID),
                applicationPID: application.processIdentifier,
                accessibilityElement: window,
                spaceIDs: Set(managedSpaceIDs),
                primarySpaceID: managedSpaceIDs.first,
                isMinimized: minimizedState(for: window),
                isHidden: hiddenState(for: window),
                isFullscreen: fullscreenState(for: window),
                isFrontmost: focusedWindowID == Int(windowID)
            )
        }
    }

    /// Captures only hidden apps, hidden windows, and minimized windows so a
    /// Dock restart can restore visibility states that macOS may otherwise clear.
    nonisolated static func captureDockRestartWindowState() -> DockRestartWindowStateSnapshot {
        let accessibilityAvailable = isAccessibilityTrusted
        let accessibilityDeadline = ProcessInfo.processInfo.systemUptime
            + DockRestartWindowStateSnapshot.accessibilityScanBudget
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var failedApplicationQueries = 0
        var accessibilityBudgetExhausted = false
        var applications: [DockRestartWindowStateSnapshot.Application] = []
        for application in NSWorkspace.shared.runningApplications {
            guard application.processIdentifier != ownPID,
                  application.bundleIdentifier != "com.apple.dock",
                  application.activationPolicy != .prohibited else {
                continue
            }

            let wasHidden = application.isHidden
            var windows: [DockRestartWindowStateSnapshot.Application.Window] = []
            if accessibilityAvailable {
                if let capturedStates = windowStates(
                    for: application.processIdentifier,
                    captureHiddenWindows: !wasHidden,
                    before: accessibilityDeadline,
                    budgetExhausted: &accessibilityBudgetExhausted
                ) {
                    windows = capturedStates
                } else if !accessibilityBudgetExhausted {
                    failedApplicationQueries += 1
                }
            }

            if wasHidden || !windows.isEmpty {
                applications.append(DockRestartWindowStateSnapshot.Application(
                    processIdentifier: application.processIdentifier,
                    wasHidden: wasHidden,
                    windows: windows
                ))
            }

            if accessibilityBudgetExhausted {
                break
            }
        }

        return DockRestartWindowStateSnapshot(
            accessibilityAvailable: accessibilityAvailable,
            applications: applications,
            failedApplicationQueries: failedApplicationQueries,
            accessibilityBudgetExhausted: accessibilityBudgetExhausted
        )
    }

    /// Reapplies previously minimized windows before hiding their apps again.
    /// This intentionally does not unhide apps or windows that were visible in
    /// the snapshot, so it cannot bring another app to the foreground.
    nonisolated static func restoreDockRestartWindowState(
        _ snapshot: DockRestartWindowStateSnapshot
    ) -> DockRestartWindowStateRestoreResult {
        var result = DockRestartWindowStateRestoreResult()
        let canRestoreWindowStates = snapshot.accessibilityAvailable && isAccessibilityTrusted
        let accessibilityDeadline = ProcessInfo.processInfo.systemUptime
            + DockRestartWindowStateSnapshot.accessibilityScanBudget

        for applicationState in snapshot.applications {
            guard let application = NSRunningApplication(
                processIdentifier: applicationState.processIdentifier
            ) else {
                continue
            }

            if canRestoreWindowStates, !result.accessibilityBudgetExhausted {
                for windowState in applicationState.windows {
                    let window = windowState.accessibilityElement

                    if windowState.wasMinimized {
                        let isMinimized = readState(
                            for: window,
                            attribute: kAXMinimizedAttribute as CFString,
                            before: accessibilityDeadline,
                            budgetExhausted: &result.accessibilityBudgetExhausted
                        )
                        if result.accessibilityBudgetExhausted { break }

                        if isMinimized != true {
                            guard let success = restoreState(
                                for: window,
                                attribute: kAXMinimizedAttribute as CFString,
                                before: accessibilityDeadline,
                                budgetExhausted: &result.accessibilityBudgetExhausted
                            ) else {
                                break
                            }
                            if success {
                                result.windowsReminimized += 1
                            } else {
                                result.failedRestorations += 1
                            }
                        }
                    }

                    if result.accessibilityBudgetExhausted { break }

                    if windowState.wasHidden {
                        let isHidden = readState(
                            for: window,
                            attribute: kAXHiddenAttribute as CFString,
                            before: accessibilityDeadline,
                            budgetExhausted: &result.accessibilityBudgetExhausted
                        )
                        if result.accessibilityBudgetExhausted { break }

                        if isHidden != true {
                            guard let success = restoreState(
                                for: window,
                                attribute: kAXHiddenAttribute as CFString,
                                before: accessibilityDeadline,
                                budgetExhausted: &result.accessibilityBudgetExhausted
                            ) else {
                                break
                            }
                            if success {
                                result.windowsRehidden += 1
                            } else {
                                result.failedRestorations += 1
                            }
                        }
                    }
                }
            }

            if applicationState.wasHidden, !application.isHidden {
                if application.hide() {
                    result.applicationsRehidden += 1
                } else {
                    result.failedRestorations += 1
                }
            }
        }

        return result
    }

    nonisolated private static func windowStates(
        for processIdentifier: pid_t,
        captureHiddenWindows: Bool,
        before deadline: TimeInterval,
        budgetExhausted: inout Bool
    ) -> [DockRestartWindowStateSnapshot.Application.Window]? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard setAccessibilityMessagingTimeout(on: applicationElement, before: deadline) else {
            budgetExhausted = true
            return nil
        }
        var windowsReference: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &windowsReference
        )
        if ProcessInfo.processInfo.systemUptime >= deadline {
            budgetExhausted = true
        }
        guard windowsError == .success,
              let windows = windowsReference as? [AXUIElement] else {
            return nil
        }

        var capturedWindows: [DockRestartWindowStateSnapshot.Application.Window] = []
        for window in windows {
            let wasMinimized = readState(
                for: window,
                attribute: kAXMinimizedAttribute as CFString,
                before: deadline,
                budgetExhausted: &budgetExhausted
            ) == true
            if budgetExhausted { break }

            let wasHidden = captureHiddenWindows && readState(
                for: window,
                attribute: kAXHiddenAttribute as CFString,
                before: deadline,
                budgetExhausted: &budgetExhausted
            ) == true
            if budgetExhausted { break }

            if wasMinimized || wasHidden {
                capturedWindows.append(DockRestartWindowStateSnapshot.Application.Window(
                    wasHidden: wasHidden,
                    wasMinimized: wasMinimized,
                    accessibilityElement: window
                ))
            }
        }
        return capturedWindows
    }

    nonisolated private static func setAccessibilityMessagingTimeout(
        on element: AXUIElement,
        before deadline: TimeInterval
    ) -> Bool {
        let remainingTime = deadline - ProcessInfo.processInfo.systemUptime
        guard remainingTime > 0.001 else { return false }
        return AXUIElementSetMessagingTimeout(element, Float(min(0.25, remainingTime))) == .success
    }

    nonisolated private static func readState(
        for window: AXUIElement,
        attribute: CFString,
        before deadline: TimeInterval,
        budgetExhausted: inout Bool
    ) -> Bool? {
        guard setAccessibilityMessagingTimeout(on: window, before: deadline) else {
            budgetExhausted = true
            return nil
        }
        let value = readBooleanAttribute(for: window, attribute: attribute)
        if ProcessInfo.processInfo.systemUptime >= deadline {
            budgetExhausted = true
        }
        return value
    }

    nonisolated private static func restoreState(
        for window: AXUIElement,
        attribute: CFString,
        before deadline: TimeInterval,
        budgetExhausted: inout Bool
    ) -> Bool? {
        guard setAccessibilityMessagingTimeout(on: window, before: deadline) else {
            budgetExhausted = true
            return nil
        }
        let error = AXUIElementSetAttributeValue(window, attribute, kCFBooleanTrue)
        if ProcessInfo.processInfo.systemUptime >= deadline {
            budgetExhausted = true
        }
        return error == .success
    }

    nonisolated private static func readBooleanAttribute(
        for element: AXUIElement,
        attribute: CFString
    ) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func orderedCurrentSpaceIDs(for windowID: Int) -> [String] {
        guard windowID > 0 else { return [] }

        let windowArray = [NSNumber(value: windowID)] as CFArray
        guard let result = spaceSwitcherCopySpacesForWindows(
            spaceSwitcherDefaultConnection(),
            7,
            windowArray
        ),
        let spaceIDs = result as? [NSNumber] else {
            return []
        }

        return spaceIDs.map { String($0.intValue) }
    }

    nonisolated private static func minimizedState(for window: AXUIElement) -> Bool? {
        readBooleanAttribute(for: window, attribute: kAXMinimizedAttribute as CFString)
    }

    nonisolated private static func hiddenState(for window: AXUIElement) -> Bool? {
        readBooleanAttribute(for: window, attribute: kAXHiddenAttribute as CFString)
    }

    private static func fullscreenState(for window: AXUIElement) -> Bool? {
        readBooleanAttribute(for: window, attribute: "AXFullScreen" as CFString)
    }

    private static func focusedWindowID() -> Int? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedReference
        ) == .success,
        let focusedReference else {
            return nil
        }
        let focusedWindow = focusedReference as! AXUIElement

        var windowID: CGWindowID = 0
        guard spaceSwitcherWindowID(focusedWindow, &windowID) == 0, windowID != 0 else {
            return nil
        }
        return Int(windowID)
    }

    @discardableResult
    static func setHidden(_ target: RuleWindowTarget, isHidden: Bool) -> Bool {
        setHiddenResult(target, isHidden: isHidden) == .success
    }

    static func setHiddenResult(_ target: RuleWindowTarget, isHidden: Bool) -> AXError {
        AXUIElementSetAttributeValue(
            target.accessibilityElement,
            kAXHiddenAttribute as CFString,
            isHidden ? kCFBooleanTrue : kCFBooleanFalse
        )
    }

    /// Read the live hidden state of a window when the application exposes it.
    static func isHidden(_ target: RuleWindowTarget) -> Bool? {
        hiddenState(for: target.accessibilityElement)
    }

    /// Read the live minimized state instead of relying only on the snapshot
    /// taken while enumerating windows. Space changes can briefly invalidate
    /// that snapshot while Accessibility is updating the window.
    static func isMinimized(_ target: RuleWindowTarget) -> Bool? {
        minimizedState(for: target.accessibilityElement)
    }

    @discardableResult
    static func setMinimized(_ target: RuleWindowTarget, isMinimized: Bool) -> Bool {
        AXUIElementSetAttributeValue(
            target.accessibilityElement,
            kAXMinimizedAttribute as CFString,
            isMinimized ? kCFBooleanTrue : kCFBooleanFalse
        ) == .success
    }

    @discardableResult
    static func raise(_ target: RuleWindowTarget) -> Bool {
        AXUIElementPerformAction(target.accessibilityElement, kAXRaiseAction as CFString) == .success
    }

    nonisolated private static var isAccessibilityTrusted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }
}

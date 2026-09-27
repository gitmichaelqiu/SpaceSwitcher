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

        return windows.compactMap { window in
            var windowID: CGWindowID = 0
            guard spaceSwitcherWindowID(window, &windowID) == 0, windowID != 0 else {
                return nil
            }

            return RuleWindowTarget(
                id: Int(windowID),
                applicationPID: application.processIdentifier,
                accessibilityElement: window,
                spaceIDs: currentSpaceIDs(for: Int(windowID))
            )
        }
    }

    static func currentSpaceIDs(for windowID: Int) -> Set<String> {
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

        return Set(spaceIDs.map { String($0.intValue) })
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

    private static var isAccessibilityTrusted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }
}

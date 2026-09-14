import ApplicationServices
import Cocoa
import Combine
import CoreGraphics

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var isAccessibilityGranted: Bool = false
    @Published var isEventSynthesisGranted: Bool = false

    var hasAccessibilityPermission: Bool {
        isAccessibilityGranted
    }

    private var becomeActiveObserver: NSObjectProtocol?

    private init() {
        checkPermissions()
        // Re-verify permissions when the application returns to the foreground.
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkPermissions()
        }
    }

    deinit {
        if let observer = becomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func checkPermissions() {
        // Check for accessibility
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        isAccessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
        isEventSynthesisGranted = CGPreflightPostEventAccess()
    }

    func requestAccessibilityPermission() {
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(axOptions)
        isAccessibilityGranted = trusted
        isEventSynthesisGranted = CGRequestPostEventAccess()
        openSystemSettings(type: "Privacy_Accessibility")
    }

    func openSystemSettings(type: String) {
        // Updated URL scheme for macOS Ventura and later
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(type)")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

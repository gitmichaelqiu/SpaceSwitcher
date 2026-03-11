import ApplicationServices
import Cocoa
import Combine

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var isAccessibilityGranted: Bool = false

    private init() {
        checkPermissions()
        // Listen for app becoming active to re-check permissions
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkPermissions()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func checkPermissions() {
        // Check for accessibility
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        self.isAccessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
    }

    func requestAccessibilityPermission() {
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(axOptions)
        self.isAccessibilityGranted = trusted
        
        // If it wasn't immediately granted, we open the settings
        if !trusted {
            openSystemSettings(type: "Privacy_Accessibility")
        }
    }

    func openSystemSettings(type: String) {
        // Updated URL scheme for macOS Ventura and later
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(type)")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

import Foundation
import ServiceManagement

class LaunchManager {
    static var isEnabled: Bool {
        let service = SMAppService.mainApp
        return service.status == .enabled
    }
    
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

import XCTest
@testable import SpaceSwitcher

@MainActor
final class HUDToastSettingsTests: XCTestCase {
    func testDefaultsToEnabledAndPersistsChanges() {
        let suiteName = "HUDToastSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = HUDToastSettings(defaults: defaults)
        XCTAssertTrue(settings.isEnabled)

        settings.isEnabled = false
        XCTAssertFalse(defaults.bool(forKey: HUDToastSettings.showHUDToastsKey))

        let reloadedSettings = HUDToastSettings(defaults: defaults)
        XCTAssertFalse(reloadedSettings.isEnabled)
    }
}

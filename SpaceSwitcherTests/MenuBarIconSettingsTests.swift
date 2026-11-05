import XCTest
@testable import SpaceSwitcher

final class MenuBarIconSettingsTests: XCTestCase {
    func testLoadsAndPersistsHiddenState() {
        let suiteName = "MenuBarIconSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: MenuBarIconSettings.hideMenuBarIconKey)
        let settings = MenuBarIconSettings(defaults: defaults)

        XCTAssertTrue(settings.isHidden)

        settings.isHidden = false
        XCTAssertFalse(defaults.bool(forKey: MenuBarIconSettings.hideMenuBarIconKey))
    }
}

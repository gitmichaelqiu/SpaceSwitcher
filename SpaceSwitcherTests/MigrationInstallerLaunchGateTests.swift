import XCTest
@testable import SpaceSwitcher

final class MigrationInstallerLaunchGateTests: XCTestCase {
    func testPreexistingStagedAppDoesNotLaunchBeforeInstallerWasObserved() {
        var gate = MigrationInstallerLaunchGate()

        XCTAssertFalse(gate.shouldLaunchStagedApplication(
            installerIsRunning: false,
            stagedApplicationIsValid: true
        ))
        XCTAssertFalse(gate.installerWasObserved)
    }

    func testValidStagedAppLaunchesOnlyAfterObservedInstallerExits() {
        var gate = MigrationInstallerLaunchGate()

        XCTAssertFalse(gate.shouldLaunchStagedApplication(
            installerIsRunning: true,
            stagedApplicationIsValid: true
        ))
        XCTAssertTrue(gate.installerWasObserved)
        XCTAssertFalse(gate.shouldLaunchStagedApplication(
            installerIsRunning: true,
            stagedApplicationIsValid: true
        ))
        XCTAssertTrue(gate.shouldLaunchStagedApplication(
            installerIsRunning: false,
            stagedApplicationIsValid: true
        ))
    }

    func testInstallerExitWithoutExpectedStagedAppDoesNotLaunch() {
        var gate = MigrationInstallerLaunchGate()

        XCTAssertFalse(gate.shouldLaunchStagedApplication(
            installerIsRunning: true,
            stagedApplicationIsValid: false
        ))
        XCTAssertFalse(gate.shouldLaunchStagedApplication(
            installerIsRunning: false,
            stagedApplicationIsValid: false
        ))
    }
}

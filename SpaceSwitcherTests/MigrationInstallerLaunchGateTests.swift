import XCTest
@testable import SpaceSwitcher

final class MigrationInstallerLaunchGateTests: XCTestCase {
    func testPreexistingStagedAppDoesNotLaunchBeforeInstallerWasObserved() {
        var gate = MigrationInstallerLaunchGate()

        XCTAssertEqual(gate.decision(
            installerIsRunning: false,
            stagedApplicationIsValid: true
        ), .waitingForInstaller)
        XCTAssertFalse(gate.installerWasObserved)
    }

    func testValidStagedAppLaunchesOnlyAfterObservedInstallerExits() {
        var gate = MigrationInstallerLaunchGate()

        XCTAssertEqual(gate.decision(
            installerIsRunning: true,
            stagedApplicationIsValid: true
        ), .waitingForInstaller)
        XCTAssertTrue(gate.installerWasObserved)
        XCTAssertEqual(gate.decision(
            installerIsRunning: true,
            stagedApplicationIsValid: true
        ), .waitingForInstaller)
        XCTAssertEqual(gate.decision(
            installerIsRunning: false,
            stagedApplicationIsValid: true
        ), .launchStagedApplication)
    }

    func testInstallerExitWaitsForStagedAppToFinishAppearing() {
        var gate = MigrationInstallerLaunchGate()
        let start = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(gate.decision(
            installerIsRunning: true,
            stagedApplicationIsValid: false,
            now: start
        ), .waitingForInstaller)
        XCTAssertEqual(gate.decision(
            installerIsRunning: false,
            stagedApplicationIsValid: false,
            now: start.addingTimeInterval(1)
        ), .waitingForStagedApplication)
        XCTAssertEqual(gate.decision(
            installerIsRunning: false,
            stagedApplicationIsValid: true,
            now: start.addingTimeInterval(5)
        ), .launchStagedApplication)
    }

    func testStagingFailureIsReportedOnlyAfterGracePeriod() {
        var gate = MigrationInstallerLaunchGate()
        let start = Date(timeIntervalSince1970: 100)

        _ = gate.decision(installerIsRunning: true, stagedApplicationIsValid: false, now: start)
        XCTAssertEqual(gate.decision(
            installerIsRunning: false,
            stagedApplicationIsValid: false,
            now: start.addingTimeInterval(1)
        ), .waitingForStagedApplication)
        XCTAssertEqual(gate.decision(
            installerIsRunning: false,
            stagedApplicationIsValid: false,
            now: start.addingTimeInterval(MigrationInstallerLaunchGate.stagedApplicationGracePeriod + 1)
        ), .stagingFailed)
    }

    func testInstallerRestartResetsPostInstallGracePeriod() {
        var gate = MigrationInstallerLaunchGate()
        let start = Date(timeIntervalSince1970: 100)

        _ = gate.decision(installerIsRunning: true, stagedApplicationIsValid: false, now: start)
        _ = gate.decision(installerIsRunning: false, stagedApplicationIsValid: false, now: start.addingTimeInterval(1))
        XCTAssertEqual(gate.decision(
            installerIsRunning: true,
            stagedApplicationIsValid: false,
            now: start.addingTimeInterval(40)
        ), .waitingForInstaller)
        XCTAssertEqual(gate.decision(
            installerIsRunning: false,
            stagedApplicationIsValid: false,
            now: start.addingTimeInterval(41)
        ), .waitingForStagedApplication)
    }
}

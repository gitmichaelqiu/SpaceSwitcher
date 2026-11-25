import Network
import XCTest
@testable import SpaceSwitcher

final class SpaceAPIReconnectPolicyTests: XCTestCase {
    func testUnavailableSocketStatesAreRetried() {
        let error = NWError.posix(.ECONNREFUSED)

        XCTAssertTrue(SpaceAPISocketReconnectPolicy.shouldRetry(after: .waiting(error)))
        XCTAssertTrue(SpaceAPISocketReconnectPolicy.shouldRetry(after: .failed(error)))
        XCTAssertTrue(SpaceAPISocketReconnectPolicy.shouldRetry(after: .cancelled))
    }

    func testPreparingAndReadySocketStatesDoNotTriggerReconnect() {
        XCTAssertFalse(
            SpaceAPISocketReconnectPolicy.shouldRetry(after: .preparing)
        )
        XCTAssertFalse(
            SpaceAPISocketReconnectPolicy.shouldRetry(after: .ready)
        )
    }
}

import XCTest
@testable import SpaceSwitcher

final class RuleSpaceTransitionDetectorTests: XCTestCase {
    func testVisibleSpaceOrderingDoesNotLookLikeASpaceChange() {
        XCTAssertFalse(
            RuleSpaceTransitionDetector.didVisibleSpacesChange(
                from: ["main-space", "external-space"],
                to: ["external-space", "main-space"]
            )
        )
    }

    func testVisibleSpaceMembershipChangeTriggersRuleEvaluation() {
        XCTAssertTrue(
            RuleSpaceTransitionDetector.didVisibleSpacesChange(
                from: ["main-space", "external-space"],
                to: ["main-space-2", "external-space"]
            )
        )
    }

    func testSwitchingFocusBetweenDisplaysDoesNotTriggerWhenVisibleSpacesAreUnchanged() {
        let visibleSpacesBeforeFocusChange: Set<String> = ["main-space", "external-space"]
        let visibleSpacesAfterFocusChange: Set<String> = ["main-space", "external-space"]

        XCTAssertFalse(
            RuleSpaceTransitionDetector.didVisibleSpacesChange(
                from: visibleSpacesBeforeFocusChange,
                to: visibleSpacesAfterFocusChange
            )
        )
    }
}

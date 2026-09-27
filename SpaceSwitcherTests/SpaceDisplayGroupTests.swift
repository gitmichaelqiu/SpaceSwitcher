import XCTest
@testable import SpaceSwitcher

final class SpaceDisplayGroupTests: XCTestCase {
    func testGroupsSpacesByDisplayAndOrdersSpacesByNumber() {
        let spaces = [
            SpaceInfo(id: "external-2", name: "Research", number: 2, displayID: "external", displayName: "External Display"),
            SpaceInfo(id: "main-2", name: "Writing", number: 2, displayID: "Main", displayName: "Built-in Retina Display"),
            SpaceInfo(id: "main-1", name: "Main", number: 1, displayID: "Main", displayName: "Built-in Retina Display"),
            SpaceInfo(id: "external-1", name: "Work", number: 1, displayID: "external", displayName: "External Display")
        ]

        let groups = SpaceDisplayGroup.make(from: spaces)

        XCTAssertEqual(groups.map(\.id), ["Main", "external"])
        XCTAssertEqual(groups.map(\.name), ["Built-in Retina Display", "External Display"])
        XCTAssertEqual(groups[0].spaces.map(\.id), ["main-1", "main-2"])
        XCTAssertEqual(groups[1].spaces.map(\.id), ["external-1", "external-2"])
    }
}

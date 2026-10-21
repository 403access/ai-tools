import XCTest
@testable import OpenCodeBar

final class SubagentOrderingTests: XCTestCase {
    private func session(_ id: String, updated: Double) -> Session {
        Session(
            id: id,
            parentID: "ses_parent",
            projectID: "project",
            agent: nil,
            model: nil,
            cost: 0,
            tokens: .zero,
            outcome: nil,
            time: Session.Time(created: updated, updated: updated, idle: nil, viewed: nil, archived: nil),
            title: id,
            subpath: nil,
            location: Session.Location(directory: nil)
        )
    }

    func testRunningComesFirstThenMostRecentlyUpdated() {
        let recent = session("ses_a", updated: 300)
        let older = session("ses_b", updated: 100)
        let runningOld = session("ses_c", updated: 50)

        let sorted = SubagentOrdering.sorted([recent, older, runningOld], activeIDs: ["ses_c"])

        XCTAssertEqual(sorted.map(\.id), ["ses_c", "ses_a", "ses_b"])
    }

    func testEqualTimestampsFallBackToIDForStableOrdering() {
        let first = session("ses_b", updated: 100)
        let second = session("ses_a", updated: 100)

        let sorted = SubagentOrdering.sorted([first, second], activeIDs: [])

        XCTAssertEqual(sorted.map(\.id), ["ses_a", "ses_b"])
    }
}

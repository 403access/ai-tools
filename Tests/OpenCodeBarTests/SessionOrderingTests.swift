import XCTest
@testable import OpenCodeBar

final class SessionOrderingTests: XCTestCase {
    private func session(_ id: String, updated: Double, created: Double? = nil) -> Session {
        Session(
            id: id,
            parentID: nil,
            projectID: "project",
            agent: nil,
            model: nil,
            cost: 0,
            tokens: .zero,
            outcome: nil,
            time: Session.Time(
                created: created ?? updated,
                updated: updated,
                idle: nil,
                viewed: nil,
                archived: nil
            ),
            title: id,
            subpath: nil,
            location: Session.Location(directory: nil)
        )
    }

    private func message(_ id: String, created: Double) -> SessionMessage {
        SessionMessage(
            id: id,
            type: "assistant",
            time: SessionMessage.Time(created: created, streamed: nil, completed: nil),
            text: nil,
            content: nil,
            model: nil,
            agent: nil,
            cost: nil,
            tokens: nil
        )
    }

    func testSessionsComeBackMostRecentlyUpdatedFirst() {
        let recent = session("ses_recent", updated: 300)
        let older = session("ses_older", updated: 100)

        let sorted = SessionOrdering.mostRecentFirst([older, recent])

        XCTAssertEqual(sorted.map(\.id), ["ses_recent", "ses_older"])
    }

    func testEqualSessionTimestampsFallBackToIDForStableOrdering() {
        let first = session("ses_b", updated: 100)
        let second = session("ses_a", updated: 100)

        let sorted = SessionOrdering.mostRecentFirst([first, second])

        XCTAssertEqual(sorted.map(\.id), ["ses_a", "ses_b"])
    }

    func testMessagesComeBackNewestFirst() {
        let older = message("msg_old", created: 100)
        let newest = message("msg_new", created: 300)

        let sorted = MessageOrdering.mostRecentFirst([older, newest])

        XCTAssertEqual(sorted.map(\.id), ["msg_new", "msg_old"])
    }
}

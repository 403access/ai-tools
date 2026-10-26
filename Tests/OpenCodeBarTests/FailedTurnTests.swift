import XCTest
@testable import OpenCodeBar

final class FailedTurnTests: XCTestCase {
    private func decode(_ json: String) throws -> SessionMessage {
        try JSONDecoder().decode(SessionMessage.self, from: Data(json.utf8))
    }

    func testDecodesStructuredErrorAndRetry() throws {
        let message = try decode("""
        {
          "id": "msg_idle",
          "type": "idle",
          "outcome": "failed",
          "time": { "created": 300 },
          "error": {
            "type": "provider.invalid-request",
            "message": "Upstream request failed: model unavailable",
            "status": 400
          },
          "retry": {
            "attempt": 2,
            "at": 290,
            "error": {
              "type": "provider.error",
              "message": "First attempt failed"
            }
          }
        }
        """)

        XCTAssertEqual(message.type, "idle")
        XCTAssertTrue(message.hasError)
        XCTAssertEqual(message.error?.displayMessage, "Upstream request failed: model unavailable")
        XCTAssertEqual(message.error?.detailLine, "provider.invalid-request · HTTP 400")
        XCTAssertEqual(message.retry?.attempt, 2)
    }

    func testSuccessfulIdleMessagesAreHidden() throws {
        let idle = try decode("""
        { "id": "msg_idle", "type": "idle", "outcome": "succeeded", "time": { "created": 300 } }
        """)

        XCTAssertFalse(idle.isVisibleStatus)
    }

    func testLatestFailedTurnFindsThePromptAndSettings() throws {
        let idle = try decode("""
        {
          "id": "msg_idle", "type": "idle", "outcome": "failed", "time": { "created": 300 },
          "error": { "type": "provider.invalid-request", "message": "nope" }
        }
        """)
        let assistant = try decode("""
        {
          "id": "msg_assistant", "type": "assistant", "time": { "created": 200 },
          "agent": "build",
          "model": { "id": "iceman-contributor-free", "providerID": "opencode-go" },
          "finish": "error", "error": { "type": "provider.invalid-request", "message": "nope" }
        }
        """)
        let user = try decode("""
        { "id": "msg_user", "type": "user", "time": { "created": 100 }, "text": "Add a dev view" }
        """)

        let turn = [idle, assistant, user].latestFailedTurn()

        XCTAssertEqual(turn?.prompt.promptText, "Add a dev view")
        XCTAssertEqual(turn?.agent, "build")
        XCTAssertEqual(turn?.model?.id, "iceman-contributor-free")
        XCTAssertEqual(turn?.model?.providerID, "opencode-go")
    }

    func testOldFailuresDoNotOfferRetry() throws {
        let success = try decode("""
        { "id": "msg_new", "type": "assistant", "time": { "created": 200 }, "content": [] }
        """)
        let assistant = try decode("""
        { "id": "msg_old", "type": "assistant", "time": { "created": 100 },
          "error": { "type": "provider.error", "message": "old" } }
        """)
        let user = try decode("""
        { "id": "msg_user", "type": "user", "time": { "created": 90 }, "text": "old prompt" }
        """)

        XCTAssertNil([success, assistant, user].latestFailedTurn(lookback: 1))
    }
}

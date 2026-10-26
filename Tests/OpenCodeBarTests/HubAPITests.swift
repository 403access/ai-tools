import XCTest
@testable import OpenCodeBar

/// Guards the JSON contract between the hub and the clients. The hub mirrors
/// OpenCode's shapes and adds a few of its own, so these fixtures double as
/// documentation of what the server must keep returning.
final class HubAPITests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testUsageResponseKeepsLastGoodPayloadWithError() throws {
        let json = """
        {
          "data": { "rolling": { "percent": 12, "resetsAt": "2026-10-21T23:00:00Z" } },
          "fetchedAt": 1792595500600,
          "stale": true,
          "error": "Go API key expired — create a new one in Console",
          "configured": true
        }
        """
        let response = try decode(HubUsageResponse.self, json)
        XCTAssertTrue(response.configured)
        XCTAssertEqual(response.stale, true)
        XCTAssertEqual(response.data?.rolling?.percent, 12)
        XCTAssertEqual(response.error?.isEmpty, false)
        XCTAssertNotNil(response.fetchedDate)
    }

    func testUsageResponseReportsUnconfiguredHub() throws {
        let json = """
        { "data": null, "fetchedAt": null, "stale": false, "error": null, "configured": false }
        """
        let response = try decode(HubUsageResponse.self, json)
        XCTAssertFalse(response.configured)
        XCTAssertNil(response.data)
        XCTAssertNil(response.fetchedDate)
    }

    func testSessionsResponseDecodesHubShape() throws {
        let json = """
        {
          "data": [
            {
              "id": "ses_1",
              "parentID": "ses_parent",
              "projectID": "prj_1",
              "agent": "build",
              "model": { "id": "deepseek-v4.1-flash", "providerID": "opencode" },
              "cost": 0.21,
              "tokens": { "input": 10, "output": 20, "reasoning": 3, "cache": { "read": 4, "write": 5 } },
              "time": { "created": 1792592046011, "updated": 1792595523652, "idle": 1792595414457 },
              "title": "Mobile app with shared server",
              "fork": {
                "sessionID": "ses_source",
                "boundary": { "type": "before", "messageID": "msg_failed" }
              },
              "location": { "directory": "/Users/example/ai-tools" }
            }
          ]
        }
        """
        let response = try decode(SessionsResponse.self, json)
        XCTAssertEqual(response.data.count, 1)
        let session = try XCTUnwrap(response.data.first)
        XCTAssertEqual(session.id, "ses_1")
        XCTAssertEqual(session.parentID, "ses_parent")
        XCTAssertEqual(session.agent, "build")
        XCTAssertEqual(session.model?.id, "deepseek-v4.1-flash")
        XCTAssertEqual(session.tokens.total, 42)
        XCTAssertEqual(session.directory, "/Users/example/ai-tools")
        XCTAssertEqual(session.fork?.sessionID, "ses_source")
        XCTAssertEqual(session.fork?.boundary?.messageID, "msg_failed")
        XCTAssertTrue(session.isFork)
        XCTAssertTrue(session.isSubagent)
    }

    func testStatsResponseDecodesCachedPayloadWithFlags() throws {
        let json = """
        {
          "data": {
            "range": { "from": 1, "to": 2 },
            "steps": 43642,
            "sessions": 570,
            "subagents": 3,
            "prompts": 99,
            "cost": 12.5,
            "tokens": { "input": 1, "output": 2, "reasoning": 3, "cache": { "read": 4, "write": 5 } },
            "tools": {
              "mode": "detail",
              "totals": { "calls": 10, "succeeded": 9, "failed": 1, "unfinished": 0 },
              "usage": [
                { "name": "shell", "calls": 6, "succeeded": 6, "failed": 0, "unfinished": 0, "durationP50": 231 },
                { "name": "edit", "calls": 4, "succeeded": 3, "failed": 1, "unfinished": 0 }
              ]
            },
            "streak": 39,
            "activeDays": 49,
            "activity": [ { "date": "2026-10-21", "steps": 1373 } ],
            "models": []
          },
          "fetchedAt": 1792595500600,
          "stale": false
        }
        """
        let response = try decode(StatsResponse.self, json)
        XCTAssertEqual(response.data.steps, 43_642)
        XCTAssertEqual(response.data.steps(onDay: "2026-10-21"), 1_373)
        XCTAssertEqual(response.data.maxSteps, 1_373)
        XCTAssertEqual(response.data.tools.usage?.count, 2)
        XCTAssertEqual(response.data.tools.usage?.first?.durationP50 ?? 0, 231)
        XCTAssertEqual(response.data.tools.totals?.successRate ?? 0, 0.9, accuracy: 0.0001)
    }

    func testSessionStatsResponseDecodesToolReliability() throws {
        let json = """
        {
          "data": {
            "sessionID": "ses_1",
            "prompts": 8,
            "steps": 208,
            "subagents": 2,
            "messages": 216,
            "tokens": { "input": 10, "output": 20, "reasoning": 3, "cache": { "read": 4, "write": 5 } },
            "cost": 0.41,
            "tools": {
              "mode": "detail",
              "totals": { "calls": 321, "succeeded": 319, "failed": 1, "unfinished": 1 },
              "usage": [
                { "name": "edit", "calls": 145, "succeeded": 144, "failed": 1, "unfinished": 0, "durationP50": 17 }
              ]
            },
            "failures": [
              {
                "name": "edit",
                "error": "No changes to apply: oldString and newString are identical.",
                "messageID": "msg_2",
                "partID": "part_3",
                "created": 1792595523652
              }
            ],
            "files": { "files": 23, "additions": 1220, "deletions": 71 },
            "time": { "created": 1792594547497, "updated": 1792607774436, "duration": 13226939 },
            "complete": true
          }
        }
        """
        let response = try decode(SessionStatsResponse.self, json)
        let stats = response.data
        XCTAssertEqual(stats.sessionID, "ses_1")
        XCTAssertEqual(stats.steps, 208)
        XCTAssertEqual(stats.totals.calls, 321)
        XCTAssertEqual(stats.files.net, 1_149)
        XCTAssertEqual(stats.failures.first?.name, "edit")
        XCTAssertEqual(stats.failures.first?.message, "No changes to apply: oldString and newString are identical.")
        XCTAssertEqual(stats.tools.usage?.first?.durationP50 ?? 0, 17)
        XCTAssertTrue(stats.complete)
        XCTAssertEqual(Fmt.duration(milliseconds: 3_600_000), "1h 0m")
        XCTAssertEqual(Fmt.milliseconds(231), "231ms")
    }

    func testHealthResponseDecodesHubAndOpenCodeStatus() throws {
        let json = """
        {
          "ok": true,
          "version": "1.0.0",
          "hub": { "version": "1.0.0", "uptime": 10440, "sessions": 570, "messages": 148, "projects": 16 },
          "opencode": {
            "connected": true,
            "url": "http://127.0.0.1:49374",
            "version": "2.1.1",
            "lastSync": 1792595515303,
            "lastError": null
          }
        }
        """
        let response = try decode(HubHealthResponse.self, json)
        XCTAssertEqual(response.hub?.sessions, 570)
        XCTAssertEqual(response.opencode?.connected, true)
        XCTAssertEqual(response.opencode?.version, "2.1.1")
    }

    func testTransportErrorsTriggerRediscovery() {
        XCTAssertTrue(APIError.transport("connection refused").shouldRediscover)
        XCTAssertTrue(APIError.unauthorized.shouldRediscover)
        XCTAssertFalse(APIError.status(503).shouldRediscover)
    }

    func testChangesResponseDecodesProjectContext() throws {
        let json = """
        {
          "data": [
            {
              "file": "Sources/App.swift",
              "patch": "--- a/Sources/App.swift\\n+++ b/Sources/App.swift\\n@@ -1 +1 @@\\n-old\\n+new\\n",
              "additions": 1,
              "deletions": 1,
              "status": "modified",
              "sessionID": "ses_1",
              "sessionTitle": "Fix the build",
              "messageID": "msg_1",
              "created": 1792595523652
            }
          ]
        }
        """
        let response = try decode(ChangesResponse.self, json)
        let change = try XCTUnwrap(response.data.first)
        XCTAssertEqual(change.displayPath, "Sources/App.swift")
        XCTAssertEqual(change.additions, 1)
        XCTAssertEqual(change.deletions, 1)
        XCTAssertEqual(change.statusLabel, "modified")
        XCTAssertEqual(change.sessionTitle, "Fix the build")
        XCTAssertEqual(change.patchLines.count, 6)
    }

    func testProjectFilesResponseDecodesGitStatus() throws {
        let json = """
        {
          "data": {
            "files": [
              { "path": "README.md" },
              { "path": "Sources/App.swift", "status": "modified" },
              { "path": "Sources/New.swift", "status": "added" },
              { "path": "Sources/Old.swift", "status": "deleted" }
            ],
            "vcs": "git",
            "changed": 3,
            "total": 4,
            "truncated": false
          }
        }
        """
        let response = try decode(ProjectFilesResponse.self, json)
        XCTAssertEqual(response.data.vcs, "git")
        XCTAssertEqual(response.data.total, 4)
        XCTAssertEqual(response.data.changed, 3)
        XCTAssertFalse(response.data.truncated)
        XCTAssertEqual(response.data.files.count, 4)
        XCTAssertFalse(response.data.files[0].isChanged)
        XCTAssertEqual(response.data.files[1].statusLabel, "Modified")
        XCTAssertEqual(response.data.files[1].directory, "Sources/")
        XCTAssertEqual(response.data.files[1].name, "App.swift")
        XCTAssertEqual(response.data.files[2].statusIcon, "plus.circle.fill")
    }

    func testToolMetadataExposesFileChanges() throws {
        let json = """
        {
          "type": "tool",
          "id": "part_1",
          "name": "edit",
          "state": {
            "status": "completed",
            "metadata": {
              "files": [
                {
                  "file": "README.md",
                  "patch": "--- a/README.md\\n+++ b/README.md\\n@@ -1 +1 @@\\n-a\\n+b\\n",
                  "additions": 1,
                  "deletions": 1,
                  "status": "modified"
                }
              ]
            }
          }
        }
        """
        let part = try decode(MessagePart.self, json)
        XCTAssertEqual(part.fileChanges.count, 1)
        XCTAssertEqual(part.fileChanges.first?.file, "README.md")
    }

    func testPendingResponseDecodesUserPromptsAndSkipsInternalItems() throws {
        let json = """
        {
          "data": [
            {
              "id": "msg_1",
              "sessionID": "ses_1",
              "type": "user",
              "time": { "created": 1792595500600 },
              "delivery": "queue",
              "payload": { "text": "Run the tests" }
            },
            {
              "id": "msg_2",
              "sessionID": "ses_1",
              "type": "compaction",
              "time": { "created": 1792595501000 },
              "delivery": "steer",
              "payload": {}
            }
          ]
        }
        """
        let response = try decode(SessionPendingResponse.self, json)
        XCTAssertEqual(response.data.count, 2)
        XCTAssertEqual(response.data[0].promptText, "Run the tests")
        XCTAssertEqual(response.data[0].delivery, .queue)
        XCTAssertEqual(response.data[0].deliveryLabel, "Queued")
        XCTAssertTrue(response.data[0].isUserPrompt)
        XCTAssertEqual(response.data[0].time.createdDate, Date(timeIntervalSince1970: 1792595500.6))
        XCTAssertNil(response.data[1].promptText)
        XCTAssertFalse(response.data[1].isUserPrompt)
        XCTAssertEqual(response.data[1].deliveryLabel, "Steer")
    }
}

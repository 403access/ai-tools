import XCTest
@testable import OpenCodeBar

final class SessionActivityTests: XCTestCase {
    private func event(_ json: String) throws -> OpenCodeEvent {
        try JSONDecoder().decode(OpenCodeEvent.self, from: Data(json.utf8))
    }

    func testToolCallBecomesTheCurrentActivity() throws {
        var activity = SessionActivity()
        let event = try event("""
        {"type":"session.tool.called","created":1700000000000,"data":{
          "sessionID":"ses_test","id":"call_1","name":"shell",
          "input":{"command":"swift build"}
        }}
        """)

        activity.apply(event, directory: "/tmp/project")

        XCTAssertEqual(activity.phase, .tool)
        XCTAssertEqual(activity.tool?.name, "shell")
        XCTAssertEqual(activity.tool?.summary, "swift build")
        XCTAssertEqual(activity.tool?.status, "running")
        XCTAssertEqual(activity.toolVerb, "Running")
    }

    func testToolSummaryStripsProjectDirectory() {
        let input = JSONValue.object([
            "filePath": .string("/tmp/project/Sources/App.swift")
        ])
        let summary = ToolInputSummary.text(name: "read", input: input, directory: "/tmp/project")
        XCTAssertEqual(summary, "Sources/App.swift")
    }

    func testTodoListIsParsedFromTodowriteInput() throws {
        var activity = SessionActivity()
        let event = try event("""
        {"type":"session.tool.called","created":1700000000000,"data":{
          "sessionID":"ses_test","id":"call_1","name":"todowrite",
          "input":{"todos":[
            {"content":"Inspect API","status":"completed","priority":"high"},
            {"content":"Build the view","status":"in_progress","priority":"high"},
            {"content":"Write tests","status":"pending","priority":"medium"}
          ]}
        }}
        """)

        activity.apply(event, directory: nil)

        XCTAssertEqual(activity.totalTodos, 3)
        XCTAssertEqual(activity.completedTodos, 1)
        XCTAssertEqual(activity.activeTodo?.content, "Build the view")
        XCTAssertEqual(activity.todoFraction, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testEmptyTodoListClearsProgress() throws {
        var activity = SessionActivity()
        activity.todos = [SessionActivity.Todo(content: "Old item", status: "pending")]

        activity.apply(try event("""
        {"type":"session.tool.called","created":1700000000000,"data":{
          "sessionID":"ses_test","id":"call_1","name":"todowrite","input":{"todos":[]}
        }}
        """), directory: nil)

        XCTAssertTrue(activity.todos.isEmpty)
    }

    func testReasoningDeltasAccumulateAndShowTheLastLine() throws {        var activity = SessionActivity()
        activity.apply(try event("""
        {"type":"session.reasoning.started","created":1700000000000,"data":{"sessionID":"ses_test"}}
        """), directory: nil)
        activity.apply(try event("""
        {"type":"session.reasoning.delta","created":1700000000100,"data":{"sessionID":"ses_test","delta":"First line.\\n"}}
        """), directory: nil)
        activity.apply(try event("""
        {"type":"session.reasoning.delta","created":1700000000200,"data":{"sessionID":"ses_test","delta":"Second line."}}
        """), directory: nil)

        XCTAssertEqual(activity.phase, .thinking)
        XCTAssertEqual(activity.detailLine, "Second line.")
    }

    func testUsageEventUpdatesLiveCostAndTokens() throws {
        var activity = SessionActivity()
        activity.apply(try event("""
        {"type":"session.usage.updated","created":1700000000000,"data":{
          "sessionID":"ses_test","cost":0.42,
          "tokens":{"input":10,"output":20,"reasoning":30,"cache":{"read":40,"write":0}}
        }}
        """), directory: nil)

        XCTAssertEqual(activity.cost, 0.42)
        XCTAssertEqual(activity.tokens?.generated, 60)
    }

    func testDeriveFromLatestAssistantMessage() throws {
        let message = try JSONDecoder().decode(SessionMessage.self, from: Data("""
        {"id":"msg_1","type":"assistant","time":{"created":1700000000000},
         "agent":"build","model":{"id":"m","providerID":"p"},
         "content":[
           {"type":"reasoning","text":"Checking the build."},
           {"type":"tool","id":"call_1","name":"shell",
            "state":{"status":"running","input":{"command":"bun test"}},
            "time":{"created":1700000001000}}
         ]}
        """.utf8))

        let activity = SessionActivity.derive(from: [message], directory: "/tmp/project")

        XCTAssertEqual(activity?.phase, .tool)
        XCTAssertEqual(activity?.tool?.summary, "bun test")
        XCTAssertEqual(activity?.stepStartedAt, message.time.createdDate)
    }

    func testFailedToolShowsError() throws {
        var activity = SessionActivity()
        activity.apply(try event("""
        {"type":"session.tool.failed","created":1700000000000,"data":{
          "sessionID":"ses_test","id":"call_1","error":{"message":"Command exited 1"}
        }}
        """), directory: nil)

        XCTAssertEqual(activity.phase, .failed)
        XCTAssertEqual(activity.detail, "Command exited 1")
    }

    func testPermissionRequestWaitsForApproval() throws {
        var activity = SessionActivity()
        activity.apply(try event("""
        {"type":"permission.asked","created":1700000000000,"data":{
          "sessionID":"ses_test","action":"bash","resources":["rm -rf build"]
        }}
        """), directory: nil)

        XCTAssertEqual(activity.phase, .waitingForPermission)
        XCTAssertEqual(activity.detail, "bash · rm -rf build")
    }

    func testDeriveFromCompletedMessageWaitsForTheNextStep() throws {
        let message = try JSONDecoder().decode(SessionMessage.self, from: Data("""
        {"id":"msg_1","type":"assistant","time":{"created":1700000000000,"completed":1700000005000},
         "agent":"build","model":{"id":"m","providerID":"p"},
         "content":[{"type":"text","text":"All done."}]}
        """.utf8))

        let activity = SessionActivity.derive(from: [message], directory: nil)

        XCTAssertEqual(activity?.phase, .starting)
        XCTAssertEqual(activity?.detail, "Waiting for the model")
    }
}

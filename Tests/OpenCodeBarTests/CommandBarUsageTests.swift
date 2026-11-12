import XCTest
@testable import OpenCodeBar

final class CommandBarUsageTests: XCTestCase {
    private func session(
        cost: Double = 0,
        tokens: TokenUsage = .zero,
        model: ModelRef? = nil
    ) -> Session {
        Session(
            id: "ses_command",
            parentID: nil,
            projectID: "prj",
            agent: nil,
            model: model,
            cost: cost,
            tokens: tokens,
            outcome: nil,
            time: Session.Time(
                created: 1_000,
                updated: 5_000,
                idle: nil,
                viewed: nil,
                archived: nil
            ),
            title: "Command bar",
            subpath: nil,
            location: Session.Location(directory: "/tmp/project")
        )
    }

    private func user(_ id: String, created: Double, text: String) -> SessionMessage {
        SessionMessage(
            id: id,
            type: "user",
            time: SessionMessage.Time(created: created, streamed: nil, completed: nil),
            text: text
        )
    }

    private func assistant(
        _ id: String,
        created: Double,
        completed: Double,
        cost: Double,
        tokens: TokenUsage,
        model: ModelRef? = nil,
        outcome: String? = nil
    ) -> SessionMessage {
        SessionMessage(
            id: id,
            type: "assistant",
            time: SessionMessage.Time(created: created, streamed: nil, completed: completed),
            text: nil,
            model: model,
            cost: cost,
            tokens: tokens,
            outcome: outcome
        )
    }

    private func tokens(input: Double, output: Double) -> TokenUsage {
        TokenUsage(
            input: input,
            output: output,
            reasoning: 0,
            cache: TokenUsage.Cache(read: 0, write: 0)
        )
    }

    func testPairsPromptsWithRepliesAndKeepsNewestFirst() {
        let model = ModelRef(id: "deepseek-v4", providerID: "opencode", variant: nil)
        let messages = [
            user("u1", created: 1_000, text: "first command"),
            assistant(
                "a1",
                created: 1_100,
                completed: 1_600,
                cost: 0.01,
                tokens: tokens(input: 10, output: 5),
                model: model,
                outcome: "completed"
            ),
            user("u2", created: 2_000, text: "second command"),
            assistant(
                "a2",
                created: 2_100,
                completed: 3_100,
                cost: 0.02,
                tokens: tokens(input: 20, output: 10),
                model: model,
                outcome: "failed"
            ),
        ]

        let usage = CommandBarUsageBuilder.build(
            session: session(),
            stats: nil,
            messages: messages
        )

        XCTAssertEqual(usage.entries.map(\.prompt), ["second command", "first command"])
        XCTAssertEqual(usage.entries.first?.cost ?? 0, 0.02, accuracy: 0.0001)
        XCTAssertEqual(usage.entries.first?.tokens.input ?? 0, 20, accuracy: 0.0001)
        XCTAssertEqual(usage.entries.first?.durationMilliseconds ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(usage.entries.last?.durationMilliseconds ?? 0, 500, accuracy: 0.0001)
        XCTAssertEqual(usage.entries.first?.outcome, "failed")
        XCTAssertEqual(usage.prompts, 2)
        XCTAssertEqual(usage.cost, 0.03, accuracy: 0.0001)
    }

    func testStatsOverrideSessionTotalsWhenAvailable() {
        let stats = SessionStats(
            sessionID: "ses_command",
            prompts: 9,
            steps: 20,
            subagents: 0,
            messages: 18,
            tokens: tokens(input: 900, output: 300),
            cost: 1.25,
            tools: Stats.Tools(mode: "detail", totals: nil, usage: nil),
            failures: [],
            files: SessionStats.Files(files: 0, additions: 0, deletions: 0),
            time: SessionStats.Time(created: 1_000, updated: 5_000, duration: 4_000, idle: nil),
            complete: true
        )

        let usage = CommandBarUsageBuilder.build(
            session: session(cost: 0.10, tokens: tokens(input: 1, output: 1)),
            stats: stats,
            messages: []
        )

        XCTAssertEqual(usage.prompts, 9)
        XCTAssertEqual(usage.cost, 1.25, accuracy: 0.0001)
        XCTAssertEqual(usage.tokens.input, 900, accuracy: 0.0001)
        XCTAssertTrue(usage.entries.isEmpty)
    }

    func testLimitsRecentEntries() {
        let messages = (0..<8).flatMap { index in
            [
                user("u\(index)", created: Double(index) * 100, text: "command \(index)"),
                assistant(
                    "a\(index)",
                    created: Double(index) * 100 + 10,
                    completed: Double(index) * 100 + 50,
                    cost: 0.001,
                    tokens: tokens(input: 1, output: 1)
                ),
            ]
        }

        let usage = CommandBarUsageBuilder.build(
            session: session(),
            stats: nil,
            messages: messages,
            limit: 3
        )

        XCTAssertEqual(usage.entries.map(\.prompt), ["command 7", "command 6", "command 5"])
        XCTAssertEqual(usage.prompts, 8)
    }
}

import XCTest
@testable import OpenCodeBar

final class UsageAnalyticsTests: XCTestCase {
    private let calendar = Calendar.current

    /// Wednesday, 18 November 2026 at noon, in the test machine's time zone.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
    }

    private func day(_ value: Int, hour: Int = 12) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 11, day: value, hour: hour)
        )!
    }

    private func session(
        id: String,
        project: String = "prj_one",
        provider: String? = "anthropic",
        cost: Double = 0,
        tokens: Double = 0,
        created: Date,
        updated: Date,
        parentID: String? = nil
    ) -> Session {
        Session(
            id: id,
            parentID: parentID,
            projectID: project,
            agent: nil,
            model: provider.map { ModelRef(id: "model", providerID: $0, variant: nil) },
            cost: cost,
            tokens: TokenUsage(input: tokens, output: 0, reasoning: 0, cache: .init(read: 0, write: 0)),
            outcome: nil,
            time: Session.Time(
                created: created.timeIntervalSince1970 * 1_000,
                updated: updated.timeIntervalSince1970 * 1_000,
                idle: nil,
                viewed: nil,
                archived: nil
            ),
            title: id,
            subpath: nil,
            location: Session.Location(directory: nil)
        )
    }

    private func stats(activity: [Stats.Activity]) -> Stats {
        Stats(
            range: Stats.Range(from: 0, to: 1),
            sessions: 0,
            subagents: 0,
            prompts: 0,
            steps: activity.reduce(0) { $0 + $1.steps },
            tokens: .zero,
            cost: 0,
            tools: Stats.Tools(mode: "count", totals: nil, usage: nil),
            activeDays: activity.filter { $0.steps > 0 }.count,
            streak: 0,
            activity: activity,
            models: []
        )
    }

    func testProvidersGroupByProviderAndRespectTheWindow() {
        let sessions = [
            session(
                id: "ses_today",
                provider: "anthropic",
                cost: 2,
                tokens: 100,
                created: day(17, hour: 9),
                updated: day(18)
            ),
            session(
                id: "ses_child",
                provider: "anthropic",
                cost: 1,
                tokens: 50,
                created: day(17, hour: 10),
                updated: day(17),
                parentID: "ses_today"
            ),
            session(
                id: "ses_openai",
                provider: "openai",
                cost: 5,
                tokens: 20,
                created: day(10),
                updated: day(10)
            ),
            session(
                id: "ses_old",
                provider: "google",
                cost: 9,
                tokens: 200,
                created: calendar.date(
                    from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)
                )!,
                updated: calendar.date(
                    from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)
                )!
            ),
        ]

        let monthly = UsageInsights.providers(
            sessions: sessions,
            range: .month,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(monthly.map(\.id), ["openai", "anthropic"])
        let anthropic = try! XCTUnwrap(monthly.first { $0.id == "anthropic" })
        XCTAssertEqual(anthropic.name, "Anthropic")
        XCTAssertEqual(anthropic.cost, 3, accuracy: 0.0001)
        XCTAssertEqual(anthropic.tokens, 150, accuracy: 0.0001)
        XCTAssertEqual(anthropic.sessions, 1)
        XCTAssertEqual(anthropic.subagents, 1)

        let weekly = UsageInsights.providers(
            sessions: sessions,
            range: .week,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(weekly.map(\.id), ["anthropic"])
    }

    func testProviderNamesUseBrandCasingAndFallBackToTheId() {
        XCTAssertEqual(UsageInsights.providerName("github-copilot"), "GitHub Copilot")
        XCTAssertEqual(UsageInsights.providerName("opencode-go"), "OpenCode Go")
        XCTAssertEqual(UsageInsights.providerName("xai"), "xAI")
        XCTAssertEqual(UsageInsights.providerName("some-new-provider"), "Some New Provider")
        XCTAssertEqual(UsageInsights.providerName("unknown"), "Unknown")
    }

    func testProjectsResolveNamesAndSortBySpend() {
        let projects = [
            "prj_one": Project(
                id: "prj_one",
                canonical: "/work/one",
                vcs: "git",
                name: "One",
                time: Project.Time(created: 0, updated: 0, active: nil),
                sandboxes: []
            ),
            "prj_two": Project(
                id: "prj_two",
                canonical: "/work/two",
                vcs: "git",
                name: "Two",
                time: Project.Time(created: 0, updated: 0, active: nil),
                sandboxes: []
            ),
        ]
        let sessions = [
            session(
                id: "ses_one",
                project: "prj_one",
                cost: 1,
                tokens: 30,
                created: day(17),
                updated: day(17)
            ),
            session(
                id: "ses_two",
                project: "prj_two",
                cost: 4,
                tokens: 60,
                created: day(17),
                updated: day(17)
            ),
        ]

        let rows = UsageInsights.projects(
            sessions: sessions,
            projects: projects,
            range: .month,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(rows.map(\.name), ["Two", "One"])
        XCTAssertEqual(rows.first?.cost ?? 0, 4, accuracy: 0.0001)
        XCTAssertEqual(rows.first?.totalSessions, 1)
    }

    func testWeekdaysAreMondayFirstAndCombineStepsWithSessionSpend() {
        let monday = day(16)
        let tuesday = day(17)
        let wednesday = day(18)
        let activity = [
            Stats.Activity(date: Fmt.dayString(monday), steps: 10),
            Stats.Activity(date: Fmt.dayString(tuesday), steps: 20),
            Stats.Activity(date: Fmt.dayString(wednesday), steps: 5),
        ]
        let sessions = [
            session(
                id: "ses_tuesday",
                cost: 2,
                tokens: 40,
                created: tuesday,
                updated: tuesday
            )
        ]

        let rows = UsageInsights.weekdays(
            stats: stats(activity: activity),
            sessions: sessions,
            range: .week,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.map(\.shortName), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(rows.map(\.steps), [10, 20, 5, 0, 0, 0, 0])
        XCTAssertEqual(rows[1].cost, 2, accuracy: 0.0001)
        XCTAssertEqual(rows[1].sessions, 1)
        XCTAssertEqual(UsageInsights.weekdayIndex(for: monday, calendar: calendar), 0)
        XCTAssertEqual(UsageInsights.weekdayIndex(for: wednesday, calendar: calendar), 2)
    }

    func testHoursCountOnlyTopLevelSessionStarts() {
        let sessions = [
            session(id: "ses_morning", created: day(18, hour: 9), updated: day(18)),
            session(
                id: "ses_morning_child",
                created: day(18, hour: 9),
                updated: day(18),
                parentID: "ses_morning"
            ),
            session(id: "ses_afternoon", created: day(18, hour: 14), updated: day(18)),
            session(id: "ses_old", created: day(1, hour: 14), updated: day(1)),
        ]

        let rows = UsageInsights.hours(
            sessions: sessions,
            range: .week,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(rows.count, 24)
        XCTAssertEqual(rows[9].sessions, 1)
        XCTAssertEqual(rows[14].sessions, 1)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.sessions }, 2)
    }

    func testPunchCardCountsWeekdayAndHour() {
        let sessions = [
            session(id: "ses_monday", created: day(16, hour: 9), updated: day(16)),
            session(id: "ses_wednesday", created: day(18, hour: 18), updated: day(18)),
        ]

        let card = UsageInsights.punchCard(
            sessions: sessions,
            range: .week,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(card.maxCount, 1)
        XCTAssertEqual(card.count(weekday: 0, hour: 9), 1)
        XCTAssertEqual(card.count(weekday: 2, hour: 18), 1)
        XCTAssertEqual(card.count(weekday: 1, hour: 9), 0)
    }

    func testTotalsCompareWithThePreviousEqualWindow() {
        let activity = [
            Stats.Activity(date: Fmt.dayString(day(18)), steps: 10),
            Stats.Activity(date: Fmt.dayString(day(11)), steps: 5),
        ]
        let sessions = [
            session(id: "ses_current", cost: 2, tokens: 20, created: day(18), updated: day(18)),
            session(id: "ses_previous", cost: 4, tokens: 80, created: day(11), updated: day(11)),
        ]

        let current = UsageInsights.totals(
            stats: stats(activity: activity),
            sessions: sessions,
            range: .week,
            now: now,
            calendar: calendar
        )
        let previous = try! XCTUnwrap(
            UsageInsights.previousTotals(
                stats: stats(activity: activity),
                sessions: sessions,
                range: .week,
                now: now,
                calendar: calendar
            )
        )

        XCTAssertEqual(current.cost, 2, accuracy: 0.0001)
        XCTAssertEqual(current.tokens, 20, accuracy: 0.0001)
        XCTAssertEqual(current.steps, 10)
        XCTAssertEqual(current.sessions, 1)
        XCTAssertEqual(previous.cost, 4, accuracy: 0.0001)
        XCTAssertEqual(previous.tokens, 80, accuracy: 0.0001)
        XCTAssertEqual(previous.steps, 5)
        XCTAssertEqual(previous.sessions, 1)
    }

    func testAllTimeHasNoPreviousWindow() {
        XCTAssertNil(
            UsageInsights.previousTotals(
                stats: stats(activity: []),
                sessions: [],
                range: .all,
                now: now,
                calendar: calendar
            )
        )
    }
}

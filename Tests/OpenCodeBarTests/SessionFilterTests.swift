import XCTest
@testable import OpenCodeBar

final class SessionFilterTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        date(year: 2026, month: 10, day: 22, hour: 12)
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func session(
        _ id: String,
        projectID: String = "project-a",
        outcome: String? = nil,
        updated: Date
    ) -> Session {
        Session(
            id: id,
            parentID: nil,
            projectID: projectID,
            agent: nil,
            model: nil,
            cost: 0,
            tokens: .zero,
            outcome: outcome,
            time: Session.Time(
                created: updated.timeIntervalSince1970 * 1_000,
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

    private func project(_ id: String, canonical: String) -> Project {
        Project(
            id: id,
            canonical: canonical,
            vcs: "git",
            name: nil,
            time: Project.Time(created: 0, updated: 0, active: nil),
            sandboxes: []
        )
    }

    func testAllTimeKeepsEverySession() {
        let old = date(year: 2020, month: 1, day: 1)
        XCTAssertTrue(SessionTimeFilter.all.contains(old, now: now, calendar: calendar))
    }

    func testTodayOnlyMatchesTheCurrentCalendarDay() {
        XCTAssertTrue(
            SessionTimeFilter.today.contains(
                date(year: 2026, month: 10, day: 22, hour: 0),
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            SessionTimeFilter.today.contains(
                date(year: 2026, month: 10, day: 21, hour: 23, minute: 59),
                now: now,
                calendar: calendar
            )
        )
    }

    func testWeekWindowStartsSevenCalendarDaysBack() {
        XCTAssertTrue(
            SessionTimeFilter.week.contains(
                date(year: 2026, month: 10, day: 16),
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            SessionTimeFilter.week.contains(
                date(year: 2026, month: 10, day: 15, hour: 23, minute: 59),
                now: now,
                calendar: calendar
            )
        )
    }

    func testMonthWindowStartsThirtyCalendarDaysBack() {
        XCTAssertTrue(
            SessionTimeFilter.month.contains(
                date(year: 2026, month: 9, day: 23),
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            SessionTimeFilter.month.contains(
                date(year: 2026, month: 9, day: 22, hour: 23, minute: 59),
                now: now,
                calendar: calendar
            )
        )
    }

    func testProjectFilterGroupsDuplicateRecordsByCanonicalPath() {
        let projects = [
            "project-a": project("project-a", canonical: "/repo/one"),
            "project-b": project("project-b", canonical: "/repo/one"),
            "project-c": project("project-c", canonical: "/repo/two"),
        ]
        let first = session("ses_first", projectID: "project-b", updated: now)
        let second = session("ses_second", projectID: "project-c", updated: now)

        let filtered = SessionFiltering.apply(
            to: [first, second],
            projectID: "project-a",
            time: .all,
            projects: projects,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(filtered.map(\.id), ["ses_first"])
    }

    func testGroupingBucketsSessionsByDayAndKeepsNewestFirst() {
        let sessions = [
            session("ses_today_old", updated: date(year: 2026, month: 10, day: 22, hour: 8)),
            session("ses_today_new", updated: date(year: 2026, month: 10, day: 22, hour: 11)),
            session("ses_yesterday", updated: date(year: 2026, month: 10, day: 21, hour: 23)),
            session("ses_week", updated: date(year: 2026, month: 10, day: 18)),
            session("ses_month", updated: date(year: 2026, month: 10, day: 1)),
            session("ses_older", updated: date(year: 2026, month: 8, day: 1)),
        ]

        let sections = SessionGrouping.groupByTime(
            sessions,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            sections.map(\.group),
            [.today, .yesterday, .previous7Days, .previous30Days, .older]
        )
        XCTAssertEqual(
            sections[0].sessions.map(\.id),
            ["ses_today_new", "ses_today_old"]
        )
        XCTAssertEqual(sections[1].sessions.map(\.id), ["ses_yesterday"])
        XCTAssertEqual(sections[2].sessions.map(\.id), ["ses_week"])
        XCTAssertEqual(sections[3].sessions.map(\.id), ["ses_month"])
        XCTAssertEqual(sections[4].sessions.map(\.id), ["ses_older"])
    }

    func testGroupingOmitsEmptyBuckets() {
        let sessions = [
            session("ses_first", updated: date(year: 2026, month: 10, day: 22, hour: 9)),
            session("ses_second", updated: date(year: 2026, month: 10, day: 22, hour: 10)),
        ]

        let sections = SessionGrouping.groupByTime(
            sessions,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(sections.map(\.group), [.today])
        XCTAssertEqual(sections[0].sessions.map(\.id), ["ses_second", "ses_first"])
    }

    func testGroupingBoundariesUseStartOfDay() {
        XCTAssertEqual(
            SessionTimeGroup.bucket(
                for: date(year: 2026, month: 10, day: 22),
                now: now,
                calendar: calendar
            ),
            .today
        )
        XCTAssertEqual(
            SessionTimeGroup.bucket(
                for: date(year: 2026, month: 10, day: 21),
                now: now,
                calendar: calendar
            ),
            .yesterday
        )
        XCTAssertEqual(
            SessionTimeGroup.bucket(
                for: date(year: 2026, month: 10, day: 15),
                now: now,
                calendar: calendar
            ),
            .previous7Days
        )
        XCTAssertEqual(
            SessionTimeGroup.bucket(
                for: date(year: 2026, month: 10, day: 14, hour: 23, minute: 59),
                now: now,
                calendar: calendar
            ),
            .previous30Days
        )
        XCTAssertEqual(
            SessionTimeGroup.bucket(
                for: date(year: 2026, month: 9, day: 22),
                now: now,
                calendar: calendar
            ),
            .previous30Days
        )
        XCTAssertEqual(
            SessionTimeGroup.bucket(
                for: date(year: 2026, month: 9, day: 21, hour: 23, minute: 59),
                now: now,
                calendar: calendar
            ),
            .older
        )
    }

    func testProjectAndTimeFiltersCombine() {
        let projects = ["project-a": project("project-a", canonical: "/repo/one")]
        let recent = session("ses_recent", updated: now)
        let old = session("ses_old", updated: date(year: 2026, month: 8, day: 1))

        let filtered = SessionFiltering.apply(
            to: [recent, old],
            projectID: "project-a",
            time: .week,
            projects: projects,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(filtered.map(\.id), ["ses_recent"])
    }

    func testStatusFilterMatchesTerminalOutcome() {
        let finished = session("ses_finished", updated: now)
        let failed = session("ses_failed", outcome: "failed", updated: now)
        let interrupted = session("ses_interrupted", outcome: "interrupted", updated: now)
        let sessions = [finished, failed, interrupted]

        func ids(_ status: SessionStatusFilter) -> [String] {
            SessionFiltering.apply(
                to: sessions,
                projectID: nil,
                time: .all,
                status: status,
                projects: [:],
                now: now,
                calendar: calendar
            ).map(\.id)
        }

        XCTAssertEqual(ids(.all), ["ses_finished", "ses_failed", "ses_interrupted"])
        XCTAssertEqual(ids(.finished), ["ses_finished"])
        XCTAssertEqual(ids(.failed), ["ses_failed"])
        XCTAssertEqual(ids(.interrupted), ["ses_interrupted"])
    }

    func testStatusFilterCombinesWithProjectAndTime() {
        let projects = ["project-a": project("project-a", canonical: "/repo/one")]
        let failedRecent = session("ses_failed_recent", outcome: "failed", updated: now)
        let failedOld = session(
            "ses_failed_old",
            outcome: "failed",
            updated: date(year: 2026, month: 8, day: 1)
        )
        let finishedRecent = session("ses_finished_recent", updated: now)

        let filtered = SessionFiltering.apply(
            to: [failedRecent, failedOld, finishedRecent],
            projectID: "project-a",
            time: .week,
            status: .failed,
            projects: projects,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(filtered.map(\.id), ["ses_failed_recent"])
    }
}

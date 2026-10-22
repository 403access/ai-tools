import XCTest
@testable import OpenCodeBar

final class ProjectOrderingTests: XCTestCase {
    private func session(
        _ id: String,
        projectID: String,
        updated: Double,
        parentID: String? = nil
    ) -> Session {
        Session(
            id: id,
            parentID: parentID,
            projectID: projectID,
            agent: nil,
            model: nil,
            cost: 0,
            tokens: .zero,
            outcome: nil,
            time: Session.Time(
                created: updated,
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

    private func project(
        _ id: String,
        canonical: String,
        vcs: String? = "git",
        updated: Double
    ) -> Project {
        Project(
            id: id,
            canonical: canonical,
            vcs: vcs,
            name: id,
            time: Project.Time(created: updated, updated: updated, active: updated),
            sandboxes: []
        )
    }

    func testRunningCountsGroupsActiveSessionsByProject() {
        let sessions = [
            session("ses_a", projectID: "prj_a", updated: 300),
            session("ses_b", projectID: "prj_a", updated: 200),
            session("ses_c", projectID: "prj_b", updated: 100),
            session("ses_d", projectID: "prj_b", updated: 50),
        ]

        let counts = ProjectOrdering.runningCounts(
            sessions: sessions,
            activeIDs: ["ses_a", "ses_c"]
        )

        XCTAssertEqual(counts["prj_a"], 1)
        XCTAssertEqual(counts["prj_b"], 1)
    }

    func testDuplicateRecordsForOneDirectoryKeepTheOneWithRunningWork() {
        let legacy = project("prj_legacy", canonical: "/tmp/work", updated: 900)
        let live = project("prj_live", canonical: "/tmp/work", updated: 100)
        let sessions = [session("ses_live", projectID: "prj_live", updated: 100)]
        let running = ProjectOrdering.runningCounts(sessions: sessions, activeIDs: ["ses_live"])

        let ordered = ProjectOrdering.ordered(
            projects: [legacy.id: legacy, live.id: live],
            runningCounts: running
        )

        XCTAssertEqual(ordered.map(\.id), ["prj_live"])
    }

    func testRunningWorkComesBeforeVCSThenRecency() {
        let running = project("prj_running", canonical: "/a", vcs: nil, updated: 10)
        let git = project("prj_git", canonical: "/b", vcs: "git", updated: 20)
        let plain = project("prj_plain", canonical: "/c", vcs: nil, updated: 30)
        let sessions = [session("ses_running", projectID: running.id, updated: 10)]
        let counts = ProjectOrdering.runningCounts(sessions: sessions, activeIDs: ["ses_running"])

        let ordered = ProjectOrdering.ordered(
            projects: [git.id: git, plain.id: plain, running.id: running],
            runningCounts: counts
        )

        XCTAssertEqual(ordered.map(\.id), ["prj_running", "prj_git", "prj_plain"])
    }

    func testRunningByProjectKeepsMostRecentlyUpdatedFirst() {
        let sessions = [
            session("ses_older", projectID: "prj", updated: 100),
            session("ses_newer", projectID: "prj", updated: 300),
        ]

        let grouped = ProjectOrdering.runningByProject(
            sessions: sessions,
            activeIDs: ["ses_older", "ses_newer"]
        )

        XCTAssertEqual(grouped["prj"]?.map(\.id), ["ses_newer", "ses_older"])
    }
}

final class UsageSeriesTests: XCTestCase {
    private func point(day: Int, steps: Int) -> DailyUsage {
        DailyUsage(
            date: Date(timeIntervalSince1970: Double(day) * 86_400),
            steps: steps,
            cost: Double(day),
            tokens: Double(day * 2)
        )
    }

    private func stats(activity: [Stats.Activity]) -> Stats {
        Stats(
            range: Stats.Range(from: 0, to: 1),
            sessions: 1,
            subagents: 0,
            prompts: 1,
            steps: activity.reduce(0) { $0 + $1.steps },
            tokens: .zero,
            cost: 0,
            tools: Stats.Tools(mode: "count", totals: nil, usage: nil),
            activeDays: activity.count,
            streak: 0,
            activity: activity,
            models: []
        )
    }

    func testBucketingSumsConsecutiveDaysAndCapsThePointCount() {
        let points = (0..<10).map { point(day: $0, steps: 10) }

        let bucketed = UsageSeries.bucketed(points, maxPoints: 4)

        XCTAssertEqual(bucketed.count, 4)
        XCTAssertEqual(bucketed.map(\.steps), [30, 30, 30, 10])
        XCTAssertEqual(bucketed.map(\.cost), [3, 12, 21, 9])
    }

    func testBucketingLeavesShortSeriesUntouched() {
        let points = (0..<5).map { point(day: $0, steps: 1) }

        XCTAssertEqual(UsageSeries.bucketed(points, maxPoints: 30), points)
    }

    func testBuildMapsActivityAndSessionTotalsToTheirCalendarDay() {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let key = Fmt.dayString(today)
        let session = Session(
            id: "ses_today",
            parentID: nil,
            projectID: "prj",
            agent: nil,
            model: nil,
            cost: 1.5,
            tokens: TokenUsage(
                input: 10,
                output: 5,
                reasoning: 2,
                cache: .init(read: 0, write: 0)
            ),
            outcome: nil,
            time: Session.Time(
                created: today.addingTimeInterval(60).timeIntervalSince1970 * 1_000,
                updated: today.addingTimeInterval(3_600).timeIntervalSince1970 * 1_000,
                idle: nil,
                viewed: nil,
                archived: nil
            ),
            title: "Today",
            subpath: nil,
            location: Session.Location(directory: nil)
        )

        let points = UsageSeries.build(
            stats: stats(activity: [.init(date: key, steps: 42)]),
            sessions: [session],
            range: .month,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(points.last?.steps, 42)
        XCTAssertEqual(points.last?.cost ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(points.last?.tokens ?? 0, 17, accuracy: 0.0001)
    }
}

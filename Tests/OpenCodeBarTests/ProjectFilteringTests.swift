import XCTest
@testable import OpenCodeBar

final class ProjectFilteringTests: XCTestCase {
    private func project(
        _ id: String,
        canonical: String,
        name: String? = nil,
        vcs: String? = "git",
        sandboxes: [String] = [],
        updated: Double = 100
    ) -> Project {
        Project(
            id: id,
            canonical: canonical,
            vcs: vcs,
            name: name,
            time: Project.Time(created: updated, updated: updated, active: updated),
            sandboxes: sandboxes
        )
    }

    func testSearchMatchesNamePathGitAndSandboxDirectories() {
        let projects = [
            project("prj_site", canonical: "/Users/me/Developer/website", name: "Website", vcs: "git"),
            project(
                "prj_sandbox",
                canonical: "/Users/me/Developer/api",
                name: "API",
                vcs: nil,
                sandboxes: ["/tmp/api-experiment"]
            ),
        ]

        XCTAssertEqual(
            projects.matchingProjectSearch("web").map(\.id),
            ["prj_site"]
        )
        XCTAssertEqual(
            projects.matchingProjectSearch("developer/api").map(\.id),
            ["prj_sandbox"]
        )
        XCTAssertEqual(
            projects.matchingProjectSearch("api-experiment").map(\.id),
            ["prj_sandbox"]
        )
        XCTAssertEqual(
            projects.matchingProjectSearch("GIT").map(\.id),
            ["prj_site"]
        )
        XCTAssertEqual(projects.matchingProjectSearch("   ").count, 2)
    }

    func testFiltersNarrowToRunningGitAndSandboxedProjects() {
        let running = project("prj_running", canonical: "/a", vcs: nil)
        let git = project("prj_git", canonical: "/b")
        let sandboxed = project("prj_sandbox", canonical: "/c", vcs: nil, sandboxes: ["/tmp/c"])
        let projects = [running, git, sandboxed]
        let counts = ["prj_running": 2]

        var query = ProjectQuery()
        query.filter = .running
        XCTAssertEqual(
            projects.applyingProjectQuery(query, runningCounts: counts).map(\.id),
            ["prj_running"]
        )

        query.filter = .git
        XCTAssertEqual(
            projects.applyingProjectQuery(query, runningCounts: counts).map(\.id),
            ["prj_git"]
        )

        query.filter = .sandboxed
        XCTAssertEqual(
            projects.applyingProjectQuery(query, runningCounts: counts).map(\.id),
            ["prj_sandbox"]
        )
    }

    func testSearchAndFilterCompose() {
        let projects = [
            project("prj_site", canonical: "/Developer/site", name: "Site"),
            project("prj_api", canonical: "/Developer/api", name: "API", vcs: nil),
        ]

        var query = ProjectQuery()
        query.search = "developer"
        query.filter = .git

        XCTAssertEqual(
            projects.applyingProjectQuery(query, runningCounts: [:]).map(\.id),
            ["prj_site"]
        )
    }

    func testNameSortIsAlphabetical() {
        let projects = [
            project("prj_c", canonical: "/c", name: "Gamma"),
            project("prj_a", canonical: "/a", name: "alpha"),
            project("prj_b", canonical: "/b", name: "Beta"),
        ]

        XCTAssertEqual(
            projects.sortedProjects(by: .name, runningCounts: [:]).map(\.id),
            ["prj_a", "prj_b", "prj_c"]
        )
    }

    func testRunningSortPutsBusiestProjectFirstThenMostRecent() {
        let busy = project("prj_busy", canonical: "/a", updated: 10)
        let recent = project("prj_recent", canonical: "/b", updated: 300)
        let older = project("prj_older", canonical: "/c", updated: 200)
        let counts = ["prj_busy": 3, "prj_recent": 1, "prj_older": 1]

        XCTAssertEqual(
            [recent, busy, older]
                .sortedProjects(by: .running, runningCounts: counts)
                .map(\.id),
            ["prj_busy", "prj_recent", "prj_older"]
        )
    }

    func testGroupingPinsRunningWorkAndBucketsByName() {
        let running = project("prj_running", canonical: "/a", name: "Alpha")
        let idle = project("prj_idle", canonical: "/b", name: "Beta")
        let counts = ["prj_running": 1]

        let recent = ProjectGrouping.groups(
            for: [running, idle],
            sort: .recent,
            runningCounts: counts
        )
        XCTAssertEqual(recent.first?.id, "running")
        XCTAssertEqual(recent.first?.projects.map(\.id), ["prj_running"])

        let named = ProjectGrouping.groups(
            for: [idle, running].sortedProjects(by: .name, runningCounts: counts),
            sort: .name,
            runningCounts: counts
        )
        XCTAssertEqual(named.map(\.title), ["A", "B"])
        XCTAssertEqual(named.compactMap { $0.projects.first?.id }, ["prj_running", "prj_idle"])
    }
}

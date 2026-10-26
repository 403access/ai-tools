import XCTest
@testable import OpenCodeBar

final class DevLogTests: XCTestCase {
    func testKeepsNewestEntriesWithinCapacity() {
        let log = DevLog(capacity: 3)

        log.record("one", category: .api)
        log.record("two", category: .sync)
        log.record("three", category: .events)
        log.record("four", category: .app)

        XCTAssertEqual(log.entries.map(\.title), ["four", "three", "two"])
        XCTAssertEqual(log.entries.map(\.category), [.app, .events, .sync])
    }

    func testAPIEntrySummarisesStatusDurationAndSize() {
        let log = DevLog(capacity: 4)

        log.api(method: "GET", path: "/api/session", status: 200, duration: 0.032, bytes: 2_048)

        XCTAssertEqual(log.entries.first?.title, "GET /api/session")
        XCTAssertEqual(log.entries.first?.detail, "200 · 32 ms · 2 KB")
        XCTAssertEqual(log.entries.first?.level, .info)
    }

    func testFailuresCountAsIssues() {
        let log = DevLog()

        log.api(method: "GET", path: "/api/x", status: 404, duration: 0.01, error: "Not found")
        log.api(method: "GET", path: "/api/y", duration: 0.01, error: "Offline")
        log.record("ok", category: .app)

        XCTAssertEqual(log.entries[0].level, .info)
        XCTAssertEqual(log.entries[1].level, .error)
        XCTAssertEqual(log.entries[2].level, .warning)
        XCTAssertEqual(log.issueCount, 2)
    }

    func testClearRemovesEntries() {
        let log = DevLog()
        log.record("one", category: .app)
        log.record("two", category: .app)

        log.clear()

        XCTAssertTrue(log.entries.isEmpty)
    }

    func testTextIsChronologicalAndMarksIssues() {
        let log = DevLog()
        log.record("first", category: .app)
        log.api(method: "GET", path: "/api/x", status: 500, duration: 0.02, error: "Boom")

        let lines = log.text.split(separator: "\n")

        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("[App] first"))
        XCTAssertTrue(lines[1].contains("[API] [error] GET /api/x"))
        XCTAssertTrue(lines[1].contains("Boom"))
    }

    func testFiltersMatchCategoriesAndIssues() {
        let log = DevLog()
        log.record("request", category: .api)
        log.record("sync issue", category: .sync, level: .error)
        log.record("notice", category: .events)

        XCTAssertEqual(
            log.entries.filter(DevLog.Filter.api.matches).map(\.title),
            ["request"]
        )
        XCTAssertEqual(
            log.entries.filter(DevLog.Filter.issues.matches).map(\.title),
            ["sync issue"]
        )
        XCTAssertEqual(
            log.entries.filter(DevLog.Filter.all.matches).count,
            3
        )
    }
}

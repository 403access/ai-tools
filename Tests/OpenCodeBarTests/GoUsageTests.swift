import XCTest
@testable import OpenCodeBar

final class GoUsageTests: XCTestCase {
    func testSubscriptionIsActiveWithAllowances() {
        let usage = GoUsage(
            rolling: .init(status: "ok", percent: 12, resetsAt: "2026-10-21T23:00:00Z"),
            weekly: .init(status: "ok", percent: 40, resetsAt: "2026-10-25T00:00:00Z"),
            monthly: .init(status: "ok", percent: 60, resetsAt: "2026-11-01T00:00:00Z")
        )

        XCTAssertEqual(usage.subscriptionStatus, "Active")
        XCTAssertFalse(usage.isRateLimited)
        XCTAssertEqual(usage.nextReset, Fmt.date(fromISO: "2026-10-21T23:00:00Z"))
    }

    func testSubscriptionReportsRateLimitAndUnknownState() {
        let limited = GoUsage(
            rolling: .init(status: "rate-limited", percent: 100, resetsAt: "2026-10-21T23:00:00Z")
        )
        XCTAssertTrue(limited.isRateLimited)
        XCTAssertEqual(limited.subscriptionStatus, "Rate limited")

        let empty = GoUsage()
        XCTAssertEqual(empty.subscriptionStatus, "Unknown")
        XCTAssertNil(empty.nextReset)
    }
}

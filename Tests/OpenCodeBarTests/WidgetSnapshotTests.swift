import XCTest
@testable import OpenCodeBar

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = WidgetSnapshot.placeholder()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testEmptySnapshotHasNoRowsOrMetrics() {
        let snapshot = WidgetSnapshot.empty(connection: .disabled)
        XCTAssertTrue(snapshot.running.isEmpty)
        XCTAssertTrue(snapshot.recent.isEmpty)
        XCTAssertNil(snapshot.metrics)
        XCTAssertNil(snapshot.usage)
        XCTAssertEqual(snapshot.connection, .disabled)
    }
}

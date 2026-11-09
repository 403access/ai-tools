import XCTest
@testable import OpenCodeBar

final class CommandPaletteTests: XCTestCase {
    private func item(
        _ id: String,
        _ kind: CommandKind,
        title: String,
        subtitle: String = "",
        keywords: [String] = [],
        recency: Date? = nil,
        running: Bool = false
    ) -> CommandItem {
        CommandItem(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            icon: .symbol("circle"),
            tint: .accent,
            badge: nil,
            badgeTint: .secondary,
            isRunning: running,
            recency: recency,
            keywords: keywords,
            action: .refresh
        )
    }

    func testProjectsOutrankSessionsAndRemainingResults() {
        let items = [
            item("app", .app, title: "Alpha"),
            item("session", .session, title: "Alpha"),
            item("navigation", .navigation, title: "Alpha"),
            item("project", .project, title: "Alpha"),
        ]

        let sections = CommandPalette.sections(
            items: items,
            favoriteIDs: [],
            query: "alpha"
        )

        XCTAssertEqual(
            sections.map(\.kind),
            [.projects, .sessions, .navigation, .apps]
        )
        XCTAssertEqual(sections.first?.items.map(\.id), ["project"])
    }

    func testFavoritesLeadAndAreNotRepeatedInTypeSections() {
        let items = [
            item("project:1", .project, title: "Website"),
            item("session:1", .session, title: "Fix login"),
        ]

        let sections = CommandPalette.sections(
            items: items,
            favoriteIDs: ["session:1"],
            query: ""
        )

        XCTAssertEqual(sections.first?.kind, .favorites)
        XCTAssertEqual(sections.first?.items.map(\.id), ["session:1"])
        XCTAssertEqual(
            sections
                .filter { $0.kind != .favorites }
                .flatMap(\.items)
                .filter { $0.kind == .session }
                .count,
            0
        )
    }

    func testSearchMatchesPathsAndKeywords() {
        let items = [
            item(
                "project:1",
                .project,
                title: "Website",
                subtitle: "/Users/me/Developer/website"
            ),
            item(
                "project:2",
                .project,
                title: "API",
                subtitle: "/Users/me/Developer/api",
                keywords: ["backend", "service"]
            ),
        ]

        let byPath = CommandPalette.sections(
            items: items,
            favoriteIDs: [],
            query: "developer"
        )
        XCTAssertEqual(byPath.first?.items.map(\.id), ["project:2", "project:1"])

        let byKeyword = CommandPalette.sections(
            items: items,
            favoriteIDs: [],
            query: "backend"
        )
        XCTAssertEqual(byKeyword.first?.items.map(\.id), ["project:2"])
    }

    func testPrefixMatchesRankAboveMidStringMatches() {
        let items = [
            item("mid", .project, title: "My API"),
            item("prefix", .project, title: "API"),
        ]

        let sections = CommandPalette.sections(
            items: items,
            favoriteIDs: [],
            query: "api"
        )

        XCTAssertEqual(sections.first?.items.map(\.id), ["prefix", "mid"])
    }

    func testFuzzySubsequenceFindsAbbreviatedQueries() {
        let items = [item("project:1", .project, title: "Website")]

        let sections = CommandPalette.sections(
            items: items,
            favoriteIDs: [],
            query: "wbst"
        )

        XCTAssertEqual(sections.first?.items.map(\.id), ["project:1"])
    }

    func testEmptyQueryShowsRecentItemsAndSkipsSystemInventory() {
        let now = Date()
        let recent = item(
            "project:recent",
            .project,
            title: "Recent",
            recency: now
        )
        let older = item(
            "project:older",
            .project,
            title: "Older",
            recency: now.addingTimeInterval(-3_600)
        )
        let app = item("app", .app, title: "Xcode")

        let sections = CommandPalette.sections(
            items: [older, recent, app],
            favoriteIDs: [],
            query: ""
        )

        XCTAssertEqual(
            sections.first?.items.map(\.id),
            ["project:recent", "project:older"]
        )
        XCTAssertFalse(sections.contains { $0.kind == .apps })
    }

    func testNoMatchProducesNoSections() {
        let items = [item("project:1", .project, title: "Website")]

        XCTAssertTrue(
            CommandPalette.sections(
                items: items,
                favoriteIDs: [],
                query: "kubernetes"
            ).isEmpty
        )
    }
}

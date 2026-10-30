import XCTest
@testable import OpenCodeBar

final class ProjectStructureTests: XCTestCase {
    private func payload(
        _ paths: [String],
        changed: Set<String> = [],
        total: Int? = nil,
        truncated: Bool = false
    ) -> ProjectFiles {
        let files = paths.map { path in
            ProjectFile(path: path, status: changed.contains(path) ? "modified" : nil)
        }
        return ProjectFiles(
            files: files,
            vcs: "git",
            changed: changed.count,
            total: total ?? files.count,
            truncated: truncated
        )
    }

    func testBuildsLayersAndContainmentEdges() throws {
        let structure = try XCTUnwrap(
            ProjectStructureBuilder.build(
                name: "Demo",
                project: payload([
                    "Sources/App/App.swift",
                    "Sources/App/Views/Home.swift",
                    "Sources/Core/Model.swift",
                    "server/src/index.ts",
                    "README.md",
                ])
            )
        )

        XCTAssertEqual(structure.columns.count, 4)
        XCTAssertEqual(structure.columns[0], [ProjectStructureBuilder.rootID])
        XCTAssertEqual(structure.columns[1].count, 3)
        XCTAssertEqual(structure.columns[2].count, 3)
        XCTAssertEqual(structure.columns[3].count, 1)

        let root = try XCTUnwrap(structure.node(structure.rootID))
        XCTAssertEqual(root.fileCount, 5)
        XCTAssertEqual(structure.totalFiles, 5)
        XCTAssertEqual(structure.totalFolders, 6)
        XCTAssertEqual(structure.edges.count, 7)

        let sources = try XCTUnwrap(structure.node("Sources"))
        XCTAssertEqual(sources.fileCount, 3)
        XCTAssertEqual(sources.depth, 1)
        XCTAssertEqual(sources.parentID, structure.rootID)

        let views = try XCTUnwrap(structure.node("Sources/App/Views"))
        XCTAssertEqual(views.depth, 3)
        XCTAssertEqual(views.parentID, "Sources/App")
        XCTAssertEqual(views.fileCount, 1)

        let readme = try XCTUnwrap(structure.node("README.md"))
        XCTAssertTrue(readme.isFile)
        XCTAssertEqual(readme.depth, 1)
        XCTAssertEqual(readme.primaryLanguage?.name, "Markdown")
    }

    func testAggregatesLanguagesAndChangedFiles() throws {
        let structure = try XCTUnwrap(
            ProjectStructureBuilder.build(
                name: "Demo",
                project: payload(
                    [
                        "Sources/App/App.swift",
                        "Sources/App/Theme.swift",
                        "Sources/Core/Model.swift",
                        "server/src/index.ts",
                        "README.md",
                    ],
                    changed: ["Sources/App/App.swift", "README.md"]
                )
            )
        )

        XCTAssertEqual(structure.changedFiles, 2)
        XCTAssertEqual(structure.languages.first?.name, "Swift")
        XCTAssertEqual(structure.languages.first?.files, 3)

        let root = try XCTUnwrap(structure.node(structure.rootID))
        XCTAssertEqual(root.changedCount, 2)

        let sources = try XCTUnwrap(structure.node("Sources"))
        XCTAssertEqual(sources.changedCount, 1)
        XCTAssertEqual(sources.primaryLanguage?.name, "Swift")

        let readme = try XCTUnwrap(structure.node("README.md"))
        XCTAssertEqual(readme.changedCount, 1)
        XCTAssertEqual(readme.languages.map(\.name), ["Markdown"])
    }

    func testCapsWideColumnsAndCountsHiddenChildren() throws {
        let paths = (0 ..< 20).map { "area\($0)/file.swift" }
        let structure = try XCTUnwrap(
            ProjectStructureBuilder.build(name: "Wide", project: payload(paths))
        )

        XCTAssertEqual(
            structure.columns[1].count,
            ProjectStructureBuilder.maxRootDirectories
        )
        XCTAssertTrue(structure.truncated)

        let root = try XCTUnwrap(structure.node(structure.rootID))
        XCTAssertEqual(root.hiddenChildren, 16)
        XCTAssertEqual(root.fileCount, 20)
    }

    func testRanksManifestsBeforeOtherRootFiles() throws {
        let structure = try XCTUnwrap(
            ProjectStructureBuilder.build(
                name: "Demo",
                project: payload([
                    "README.md",
                    "LICENSE",
                    "Package.swift",
                    ".gitignore",
                    "Sources/App/App.swift",
                ])
            )
        )

        let names = structure.columns[1].compactMap { structure.node($0)?.name }
        XCTAssertEqual(names, ["Sources", "Package.swift", "README.md"])
    }

    func testCountsHiddenChildrenOfVisibleParents() throws {
        let structure = try XCTUnwrap(
            ProjectStructureBuilder.build(
                name: "Demo",
                project: payload([
                    "Sources/A/a.swift",
                    "Sources/B/b.swift",
                    "Sources/C/c.swift",
                    "Sources/D/d.swift",
                    "Sources/E/e.swift",
                    "server/src/index.ts",
                    "website/docs/index.md",
                    "Tests/AppTests/AppTests.swift",
                ])
            )
        )

        let sources = try XCTUnwrap(structure.node("Sources"))
        XCTAssertEqual(
            sources.hiddenChildren,
            5 - 3,
            "Round-robin gives Sources a third child before the column fills"
        )
        XCTAssertEqual(structure.columns[2].count, ProjectStructureBuilder.maxColumnNodes)
    }

    func testLayoutKeepsEveryNodeOnTheCanvas() throws {
        let structure = try XCTUnwrap(
            ProjectStructureBuilder.build(
                name: "Demo",
                project: payload([
                    "Sources/App/App.swift",
                    "Sources/App/Views/Home.swift",
                    "Sources/App/Views/Parts/Row.swift",
                    "Sources/Core/Model.swift",
                    "server/src/index.ts",
                    "website/docs/index.md",
                    "README.md",
                ])
            )
        )
        let layout = ProjectStructureLayout(structure: structure)

        XCTAssertEqual(layout.items.count, structure.nodes.count)
        XCTAssertEqual(layout.items.count, layout.frames.count)

        let root = try XCTUnwrap(layout.frames[structure.rootID])
        XCTAssertGreaterThanOrEqual(root.minY, ProjectStructureLayout.padding)
        XCTAssertEqual(root.minX, ProjectStructureLayout.padding, accuracy: 0.001)

        for item in layout.items {
            XCTAssertGreaterThanOrEqual(item.frame.minY, ProjectStructureLayout.padding)
            XCTAssertLessThanOrEqual(item.frame.maxY, layout.size.height)
            XCTAssertLessThanOrEqual(item.frame.maxX, layout.size.width)
            XCTAssertEqual(layout.frames[item.node.id], item.frame)
        }

        // Ten nodes at 46pt with 12pt gaps stay inside a compact panel.
        XCTAssertLessThan(layout.size.height, 650)
    }

    func testOmitsEmptyProjects() {
        let empty = ProjectFiles(
            files: [],
            vcs: "git",
            changed: 0,
            total: 0,
            truncated: false
        )
        XCTAssertNil(ProjectStructureBuilder.build(name: "Empty", project: empty))
    }
}

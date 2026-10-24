import XCTest
@testable import OpenCodeBar

final class ChangesTests: XCTestCase {
    private func group(_ path: String, status: String = "modified") -> FileChangeGroup {
        FileChangeGroup(
            path: path,
            changes: [
                FileChange(
                    file: path,
                    patch: "+line\n",
                    additions: 1,
                    deletions: 0,
                    status: status,
                    sessionID: "session",
                    sessionTitle: "Session",
                    messageID: "message",
                    created: 1
                ),
            ]
        )
    }

    func testTreeReusesProjectFileOrderingAndCounts() {
        let tree = FileChangeTree.nodes(from: [
            group("b.swift"),
            group("a/one.swift"),
            group("a/two.swift"),
        ])

        XCTAssertEqual(tree.map(\.name), ["a", "b.swift"])
        XCTAssertEqual(tree.map(\.fileCount), [2, 1])
        XCTAssertEqual(tree.map(\.changedCount), [2, 1])

        let folder = tree[0]
        XCTAssertTrue(folder.isDirectory)
        XCTAssertEqual(folder.children.map(\.path), ["a/one.swift", "a/two.swift"])

        let file = folder.children[0]
        XCTAssertFalse(file.isDirectory)
        XCTAssertEqual(file.file?.status, "modified")
    }

    func testRowsIncludeOnlyChildrenOfExpandedFolders() {
        let groups = [
            group("a/one.swift"),
            group("a/nested/two.swift"),
            group("root.swift"),
        ]

        let collapsed = FileChangeTree.rows(from: groups, expanded: [])
        XCTAssertEqual(collapsed.map(\.node.path), ["a", "root.swift"])

        let oneLevel = FileChangeTree.rows(from: groups, expanded: ["a"])
        XCTAssertEqual(oneLevel.map(\.node.path), ["a", "a/nested", "a/one.swift", "root.swift"])
        XCTAssertEqual(oneLevel.map(\.depth), [0, 1, 1, 0])

        let allOpen = FileChangeTree.rows(
            from: groups,
            expanded: ["a", "a/nested"]
        )
        XCTAssertEqual(
            allOpen.map(\.node.path),
            ["a", "a/nested", "a/nested/two.swift", "a/one.swift", "root.swift"]
        )
        XCTAssertEqual(allOpen.map(\.depth), [0, 1, 2, 1, 0])
    }

    func testTopLevelDirectoriesRevealFirstFolderOnly() {
        let groups = [
            group("root.swift"),
            group("a/one.swift"),
            group("a/nested/two.swift"),
            group("b/three.swift"),
        ]

        XCTAssertEqual(FileChangeTree.topLevelDirectories(from: groups), ["a", "b"])
    }
}

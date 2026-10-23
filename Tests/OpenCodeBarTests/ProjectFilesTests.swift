import XCTest
@testable import OpenCodeBar

final class ProjectFilesTests: XCTestCase {
    private func file(_ path: String, _ status: String? = nil) -> ProjectFile {
        ProjectFile(path: path, status: status)
    }

    func testTreeGroupsByDirectoryAndSortsDirectoriesFirst() {
        let tree = ProjectFileTree.nodes(from: [
            file("b.txt"),
            file("a/file10.txt"),
            file("a/file2.txt"),
            file("a/nested/deep.txt"),
            file("z.txt"),
        ])

        XCTAssertEqual(tree.map(\.name), ["a", "b.txt", "z.txt"])
        XCTAssertEqual(tree.map(\.path), ["a", "b.txt", "z.txt"])

        let a = tree[0]
        XCTAssertTrue(a.isDirectory)
        XCTAssertEqual(a.children.map(\.name), ["nested", "file2.txt", "file10.txt"])

        let nested = a.children[0]
        XCTAssertTrue(nested.isDirectory)
        XCTAssertEqual(nested.path, "a/nested")
        XCTAssertEqual(nested.children.map(\.path), ["a/nested/deep.txt"])
    }

    func testTreeAggregatesFileAndChangeCounts() {
        let tree = ProjectFileTree.nodes(from: [
            file("root.txt"),
            file("src/main.swift", "modified"),
            file("src/nested/one.swift", "added"),
        ])

        XCTAssertEqual(tree.map(\.name), ["src", "root.txt"])

        let src = tree[0]
        XCTAssertEqual(src.fileCount, 2)
        XCTAssertEqual(src.changedCount, 2)

        let nested = src.children[0]
        XCTAssertEqual(nested.fileCount, 1)
        XCTAssertEqual(nested.changedCount, 1)
        XCTAssertEqual(nested.children[0].file?.status, "added")
        XCTAssertEqual(nested.children[0].changedCount, 1)

        let root = tree[1]
        XCTAssertFalse(root.isDirectory)
        XCTAssertEqual(root.fileCount, 1)
        XCTAssertEqual(root.changedCount, 0)
    }

    func testFilteredFilesDoNotCreateEmptyDirectories() {
        let tree = ProjectFileTree.nodes(from: [
            file("src/feature/main.swift"),
        ])

        XCTAssertEqual(tree.map(\.path), ["src"])
        XCTAssertEqual(tree[0].children.map(\.path), ["src/feature"])
        XCTAssertEqual(tree[0].children[0].children.map(\.path), ["src/feature/main.swift"])
        XCTAssertEqual(tree[0].fileCount, 1)
    }

    func testAncestorDirectoriesExposeEveryFolderAboveAFile() {
        XCTAssertEqual(file("root.txt").ancestorDirectories, [])
        XCTAssertEqual(
            file("src/feature/main.swift").ancestorDirectories,
            ["src", "src/feature"]
        )
        XCTAssertEqual(file("a//b.txt").ancestorDirectories, ["a"])
    }
}

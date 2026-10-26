import XCTest
@testable import OpenCodeBar

final class GitInfoTests: XCTestCase {
    private func commit(
        _ hash: String,
        parents: [String] = [],
        subject: String = "Commit",
        refs: [String] = []
    ) -> GitCommit {
        let person = GitPerson(name: "Tester", email: "test@example.com", time: 0)
        return GitCommit(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            parents: parents,
            author: person,
            committer: person,
            subject: subject,
            refs: refs
        )
    }

    func testLinearHistoryUsesOneLane() {
        let rows = GitGraph.rows(for: [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a"),
        ])

        XCTAssertEqual(rows.map(\.lane), [0, 0, 0])
        XCTAssertEqual(rows.map(\.rail), ["●", "●", "●"])
    }

    func testMergeOpensAndClosesASecondLane() {
        let rows = GitGraph.rows(for: [
            commit("merge", parents: ["main", "feature"]),
            commit("main", parents: ["root"]),
            commit("feature", parents: ["root"]),
            commit("root"),
        ])

        XCTAssertEqual(rows.map(\.lane), [0, 0, 1, 0])
        XCTAssertEqual(rows[0].rail, "●")
        XCTAssertEqual(rows[1].rail, "● │")
        XCTAssertEqual(rows[2].rail, "│ ●")
        XCTAssertEqual(rows[3].rail, "●")
    }

    func testDecorationDropsHeadArrow() {
        let decorated = commit(
            "a",
            refs: ["HEAD -> main", "origin/main", "tag: v1"]
        )

        XCTAssertEqual(decorated.displayRefs, ["main", "origin/main", "tag: v1"])
    }

    func testDecodesRepositoryPayload() throws {
        let json = """
        {
          "root": "/tmp/project",
          "branch": "main",
          "head": {
            "hash": "abc",
            "shortHash": "abc",
            "parents": [],
            "author": { "name": "Ada", "email": "ada@example.com", "time": 1700000000000 },
            "committer": { "name": "Ada", "email": "ada@example.com", "time": 1700000000000 },
            "subject": "Initial",
            "refs": ["HEAD -> main"]
          },
          "dirty": 2,
          "ahead": 1,
          "behind": 0,
          "branches": [
            {
              "name": "main",
              "hash": "abc",
              "current": true,
              "upstream": "origin/main",
              "ahead": 1,
              "behind": 0
            }
          ],
          "tags": [],
          "commits": [],
          "total": 1,
          "truncated": false
        }
        """

        let repository = try JSONDecoder().decode(
            GitRepository.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(repository.branchLabel, "main")
        XCTAssertEqual(repository.head?.subject, "Initial")
        XCTAssertEqual(repository.branches.first?.upstream, "origin/main")
        XCTAssertEqual(repository.summary.dirty, 2)
    }
}

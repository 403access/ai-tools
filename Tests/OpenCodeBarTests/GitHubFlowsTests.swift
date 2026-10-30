import XCTest
@testable import OpenCodeBar

final class GitHubFlowsTests: XCTestCase {
    func testDecodesRunStagesAndChecks() throws {
        let json = """
        {
          "data": {
            "repository": {
              "owner": "acme",
              "name": "storefront",
              "url": "https://github.com/acme/storefront",
              "remote": "git@github.com:acme/storefront.git"
            },
            "branch": "main",
            "runs": [
              {
                "id": 4821,
                "runNumber": 4821,
                "attempt": 1,
                "workflowID": 12,
                "workflowName": "CI",
                "workflowPath": ".github/workflows/ci.yml",
                "event": "push",
                "status": "running",
                "branch": "main",
                "sha": "4f2a1cbe9b24eabc76375699ab27309f901cce5",
                "shortSHA": "4f2a1cb",
                "title": "feat: checkout summary v2",
                "actor": { "login": "kenji" },
                "createdAt": 1700000000000,
                "startedAt": 1700000000000,
                "durationMs": 372000,
                "htmlURL": "https://github.com/acme/storefront/actions/runs/4821"
              }
            ],
            "run": {
              "id": 4821,
              "runNumber": 4821,
              "attempt": 1,
              "workflowID": 12,
              "workflowName": "CI",
              "event": "push",
              "status": "running",
              "branch": "main",
              "sha": "4f2a1cbe9b24eabc76375699ab27309f901cce5",
              "shortSHA": "4f2a1cb",
              "title": "feat: checkout summary v2",
              "createdAt": 1700000000000,
              "durationMs": 372000,
              "htmlURL": "https://github.com/acme/storefront/actions/runs/4821",
              "jobs": [
                {
                  "id": 1,
                  "name": "integration-tests",
                  "status": "running",
                  "durationMs": 192000,
                  "labels": ["ubuntu-latest"],
                  "htmlURL": "https://github.com/acme/storefront/actions/runs/4821/job/1",
                  "stage": 1,
                  "steps": [
                    {
                      "number": 1,
                      "name": "Run integration suite",
                      "status": "running",
                      "durationMs": 192000
                    }
                  ]
                }
              ],
              "stages": [
                {
                  "index": 1,
                  "name": "Test",
                  "status": "running",
                  "jobs": [
                    {
                      "id": 1,
                      "name": "integration-tests",
                      "status": "running",
                      "durationMs": 192000,
                      "labels": ["ubuntu-latest"],
                      "htmlURL": "https://github.com/acme/storefront/actions/runs/4821/job/1",
                      "stage": 1,
                      "steps": [
                        {
                          "number": 1,
                          "name": "Run integration suite",
                          "status": "running",
                          "durationMs": 192000
                        }
                      ]
                    }
                  ]
                }
              ],
              "checks": [
                {
                  "id": 9,
                  "name": "integration-tests",
                  "status": "running",
                  "durationMs": 192000,
                  "annotations": [
                    {
                      "path": "tests/checkout.spec.ts",
                      "startLine": 42,
                      "endLine": 42,
                      "level": "warning",
                      "message": "Retried POST /v1/checkout once (ECONNRESET)"
                    }
                  ]
                }
              ]
            },
            "commit": {
              "sha": "4f2a1cbe9b24eabc76375699ab27309f901cce5",
              "shortSHA": "4f2a1cb",
              "message": "feat: checkout summary v2",
              "authorName": "Kenji Mori",
              "additions": 412,
              "deletions": 88,
              "changedFiles": 12,
              "url": "https://github.com/acme/storefront/commit/4f2a1cb"
            },
            "generatedAt": 1700000372000
          }
        }
        """

        let response = try JSONDecoder().decode(
            GitHubFlowsResponse.self,
            from: Data(json.utf8)
        )
        let flows = try XCTUnwrap(response.data)
        XCTAssertEqual(flows.repository.fullName, "acme/storefront")
        XCTAssertEqual(flows.branch, "main")
        XCTAssertEqual(flows.runs.count, 1)

        let detail = try XCTUnwrap(flows.run)
        XCTAssertEqual(detail.run.title, "feat: checkout summary v2")
        XCTAssertEqual(detail.run.status, .running)
        XCTAssertEqual(detail.stages.first?.name, "Test")
        XCTAssertEqual(detail.jobs.first?.steps.first?.durationMs, 192_000)
        XCTAssertEqual(detail.checks.first?.annotations.first?.level, "warning")
        XCTAssertEqual(detail.checks.first?.annotations.first?.startLine, 42)
        XCTAssertEqual(flows.commit?.additions, 412)
        XCTAssertEqual(flows.commit?.changedFiles, 12)
    }

    func testUnknownStatusDoesNotFailDecoding() throws {
        let json = """
        {
          "id": 1,
          "runNumber": 1,
          "attempt": 1,
          "workflowID": 1,
          "workflowName": "CI",
          "event": "push",
          "status": "brand_new_state",
          "branch": "main",
          "sha": "abc",
          "shortSHA": "abc",
          "title": "Run",
          "createdAt": 0,
          "durationMs": 0,
          "htmlURL": "https://github.com/acme/storefront/actions/runs/1"
        }
        """

        let run = try JSONDecoder().decode(GitHubFlowRun.self, from: Data(json.utf8))
        XCTAssertEqual(run.status, .unknown)
    }
}

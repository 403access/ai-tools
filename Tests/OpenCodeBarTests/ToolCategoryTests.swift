import XCTest
@testable import OpenCodeBar

final class ToolCategoryTests: XCTestCase {
    func testFileToolsAreLibrary() {
        for name in ["read", "write", "edit", "apply_patch", "grep", "glob"] {
            XCTAssertEqual(ToolCategory.classify(name), .library, name)
        }
    }

    func testShellToolsAreOS() {
        for name in ["bash", "shell", "execute", "grepshell"] {
            XCTAssertEqual(ToolCategory.classify(name), .os, name)
        }
    }

    func testAgentAndWebToolsAreApps() {
        for name in ["task", "subagent", "skill", "question", "webfetch", "websearch"] {
            XCTAssertEqual(ToolCategory.classify(name), .apps, name)
        }
    }

    func testNamespacedToolsAreMCP() {
        for name in [
            "eu-news-news_list_articles",
            "rea_open_bundle_resources",
            "mcp__server__tool",
        ] {
            XCTAssertEqual(ToolCategory.classify(name), .mcp, name)
        }
    }

    func testUnknownSingleWordIsOther() {
        XCTAssertEqual(ToolCategory.classify("customtool"), .other)
        XCTAssertEqual(ToolCategory.classify(""), .other)
    }

    func testUsageCarriesCategory() {
        let tool = Stats.ToolUsage(
            name: "bash",
            calls: 3,
            succeeded: 2,
            failed: 1,
            unfinished: 0,
            durationP50: 42
        )
        XCTAssertEqual(tool.category, .os)
    }
}

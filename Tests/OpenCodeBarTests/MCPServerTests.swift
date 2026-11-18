import XCTest
@testable import OpenCodeBar

final class MCPServerTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
        super.tearDown()
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencodebar-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        return directory
    }

    @discardableResult
    private func write(_ contents: String, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsGlobalAndProjectConfigs() throws {
        let global = try temporaryDirectory()
        let project = try temporaryDirectory()
        try write(
            """
            {
              "mcp": {
                "servers": {
                  "opencodebar": {
                    "type": "local",
                    "command": ["bun", "server/src/mcp/server.ts"],
                    "cwd": "."
                  },
                  "docs": {
                    "type": "remote",
                    "url": "https://example.test/mcp"
                  }
                }
              }
            }
            """,
            named: "opencode.json",
            in: global,
        )
        try write(
            """
            { "mcpServers": { "project-tool": { "command": ["npx", "thing"] } } }
            """,
            named: "opencode.json",
            in: project,
        )

        let snapshot = MCPConfiguration.load(
            globalDirectory: global,
            repositoryDirectory: project,
        )

        XCTAssertEqual(snapshot.configFiles.count, 2)
        XCTAssertEqual(snapshot.servers.map(\.name), ["docs", "opencodebar", "project-tool"])
        XCTAssertTrue(snapshot.isOpenCodeBarRegistered)
        XCTAssertEqual(snapshot.servers.first { $0.name == "opencodebar" }?.type, "local")
        XCTAssertEqual(
            snapshot.servers.first { $0.name == "opencodebar" }?.detail,
            "bun server/src/mcp/server.ts",
        )
        XCTAssertEqual(snapshot.servers.first { $0.name == "docs" }?.scope, .global)
        XCTAssertEqual(snapshot.servers.first { $0.name == "project-tool" }?.scope, .project)
    }

    func testReadsJSONCCommentsWithoutBreakingStrings() throws {
        let global = try temporaryDirectory()
        try write(
            """
            {
              // The local server, launched over stdio.
              "mcp": {
                "servers": {
                  /* The URL is a string, not a comment: https://example.test */
                  "remote": { "type": "remote", "url": "https://example.test/mcp" },
                }
              }
            }
            """,
            named: "opencode.jsonc",
            in: global,
        )

        let snapshot = MCPConfiguration.load(globalDirectory: global, repositoryDirectory: nil)

        XCTAssertTrue(snapshot.errors.isEmpty)
        XCTAssertEqual(snapshot.servers.map(\.name), ["remote"])
        XCTAssertEqual(snapshot.servers.first?.detail, "https://example.test/mcp")
    }

    func testAcceptsDirectMCPMap() throws {
        let global = try temporaryDirectory()
        try write(
            """
            {
              "mcp": {
                "one": { "command": ["bun", "one.ts"] },
                "two": { "url": "https://example.test/two" }
              }
            }
            """,
            named: "opencode.json",
            in: global,
        )

        let snapshot = MCPConfiguration.load(globalDirectory: global, repositoryDirectory: nil)

        XCTAssertEqual(snapshot.servers.map(\.name), ["one", "two"])
        XCTAssertEqual(snapshot.servers.first?.type, "local")
        XCTAssertEqual(snapshot.servers.last?.type, "remote")
    }

    func testReportsBrokenConfigAndKeepsValidOnes() throws {
        let global = try temporaryDirectory()
        try write("{ not json", named: "opencode.json", in: global)
        try write(
            """
            { "mcpServers": { "ok": { "command": ["bun", "ok.ts"] } } }
            """,
            named: "opencode.jsonc",
            in: global,
        )

        let snapshot = MCPConfiguration.load(globalDirectory: global, repositoryDirectory: nil)

        XCTAssertEqual(snapshot.servers.map(\.name), ["ok"])
        XCTAssertFalse(snapshot.errors.isEmpty)
        XCTAssertFalse(snapshot.isOpenCodeBarRegistered)
    }
}
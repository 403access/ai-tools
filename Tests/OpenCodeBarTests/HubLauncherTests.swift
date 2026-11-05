import XCTest
@testable import OpenCodeBar

final class HubLauncherTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HubLauncherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testFindsServerInsideCheckout() throws {
        let server = root.appendingPathComponent("server", isDirectory: true)
        try makeServer(at: server)

        let found = HubLauncher.findServer(in: [root])

        XCTAssertEqual(found, server.standardizedFileURL)
    }

    func testFindsServerWhenFolderItselfIsSelected() throws {
        let server = root.appendingPathComponent("server", isDirectory: true)
        try makeServer(at: server)

        let found = HubLauncher.findServer(in: [server])

        XCTAssertEqual(found, server.standardizedFileURL)
    }

    func testRejectsFolderWithoutHubIndex() throws {
        let server = root.appendingPathComponent("server", isDirectory: true)
        try makeServer(at: server)
        try FileManager.default.removeItem(at: server.appendingPathComponent("src/index.ts"))

        XCTAssertNil(HubLauncher.findServer(in: [server]))
    }

    func testRejectsDifferentPackage() throws {
        let server = root.appendingPathComponent("server", isDirectory: true)
        try makeServer(at: server, name: "some-other-server")

        XCTAssertNil(HubLauncher.findServer(in: [server]))
    }

    func testSkipsMissingCandidates() throws {
        let server = root.appendingPathComponent("server", isDirectory: true)
        try makeServer(at: server)

        let found = HubLauncher.findServer(in: [
            root.appendingPathComponent("missing", isDirectory: true),
            root,
        ])

        XCTAssertEqual(found, server.standardizedFileURL)
    }

    private func makeServer(at directory: URL, name: String = "opencodebar-hub") throws {
        let source = directory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("// hub entry point\n".utf8).write(to: source.appendingPathComponent("index.ts"))
        try Data("{\"name\":\"\(name)\"}\n".utf8)
            .write(to: directory.appendingPathComponent("package.json"))
    }
}

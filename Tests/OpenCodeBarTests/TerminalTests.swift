import XCTest
@testable import OpenCodeBar

final class TerminalTests: XCTestCase {
    func testDecodesTerminalEnvelope() throws {
        let json = """
        {
          "data": [
            {
              "id": "pty_1",
              "title": "Build",
              "command": "/bin/zsh",
              "args": ["-l"],
              "cwd": "/tmp/project",
              "status": "running",
              "pid": 4321,
              "location": "/tmp/project"
            },
            {
              "id": "pty_2",
              "title": "Done",
              "command": "/bin/bash",
              "args": [],
              "cwd": "/tmp/other",
              "status": "exited",
              "pid": 99,
              "exitCode": 1,
              "location": "/tmp/other"
            }
          ]
        }
        """
        let envelope = try JSONDecoder().decode(
            TerminalsEnvelope.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(envelope.data.count, 2)
        XCTAssertEqual(envelope.data[0].commandLine, "/bin/zsh -l")
        XCTAssertTrue(envelope.data[0].isRunning)
        XCTAssertEqual(envelope.data[1].exitCode, 1)
        XCTAssertFalse(envelope.data[1].isRunning)
    }

    func testDecodesHostTerminalAndNormalizesContents() throws {
        let detail = try JSONDecoder().decode(
            HostTerminalDetail.self,
            from: Data(
                """
                {
                  "id": "ttys001",
                  "tty": "/dev/ttys001",
                  "app": "Terminal",
                  "title": "Build",
                  "busy": true,
                  "processes": ["login", "-zsh"],
                  "window": 3,
                  "tab": 1,
                  "contents": "echo hi  \\r\\nhi\\r\\n$ "
                }
                """.utf8
            )
        )

        XCTAssertEqual(detail.displayText, "echo hi\nhi\n$")
        XCTAssertEqual(detail.processes.last, "-zsh")
    }

    func testHostTerminalFallbacks() {
        let terminal = HostTerminal(
            id: "ttys002",
            tty: "/dev/ttys002",
            app: "Terminal",
            title: "  ",
            busy: false,
            processes: ["login", "-zsh"],
            window: 2,
            tab: 1
        )
        XCTAssertEqual(terminal.displayTitle, "-zsh")
        XCTAssertEqual(terminal.shortTTY, "ttys002")
        XCTAssertEqual(terminal.locationLabel, "window 2 · tab 1")
    }

    func testSocketRequestKeepsLocationInTheQuery() throws {
        let api = HubAPI(
            location: HubLocation(url: URL(string: "http://127.0.0.1:8787")!, token: "tok")
        )
        let request = try api.terminalSocketRequest(
            id: "pty_1",
            location: "/tmp/project",
            cursor: 42
        )
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.scheme, "ws")
        XCTAssertEqual(components.host, "127.0.0.1")
        XCTAssertEqual(components.port, 8787)
        XCTAssertEqual(components.path, "/api/terminals/pty_1/socket")
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }),
            ["location": "/tmp/project", "cursor": "42"]
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testCreateRequestOmitsEmptyOptionals() throws {
        let request = TerminalCreateRequest(
            title: nil,
            cwd: "/tmp/project",
            command: nil,
            location: "/tmp/project"
        )
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)
        ) as? [String: Any]

        XCTAssertEqual(object?["cwd"] as? String, "/tmp/project")
        XCTAssertEqual(object?["location"] as? String, "/tmp/project")
        XCTAssertNil(object?["title"])
        XCTAssertNil(object?["command"])
    }
}

import Foundation

/// One pseudo-terminal owned by the OpenCode service and proxied by the hub.
/// Mirrors `Terminal` in `server/src/types.ts`.
struct SystemTerminal: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var command: String
    var args: [String]
    var cwd: String
    var status: String
    var pid: Int
    var exitCode: Int?
    /// OpenCode location (working directory) that owns this terminal.
    var location: String

    var isRunning: Bool { status == "running" }

    var commandLine: String {
        ([command] + args).joined(separator: " ")
    }

    var locationLabel: String {
        (location as NSString).abbreviatingWithTildeInPath
    }

    var cwdLabel: String {
        (cwd as NSString).abbreviatingWithTildeInPath
    }
}

struct TerminalsEnvelope: Decodable {
    let data: [SystemTerminal]
}

struct TerminalEnvelope: Decodable {
    let data: SystemTerminal
}

struct TerminalCreateRequest: Encodable {
    var title: String?
    var cwd: String?
    var command: String?
    var location: String?
}

struct TerminalUpdateRequest: Encodable {
    var title: String?
    var size: TerminalSize?
    var location: String?
}

struct TerminalSize: Codable, Equatable, Sendable {
    var rows: Int
    var cols: Int
}

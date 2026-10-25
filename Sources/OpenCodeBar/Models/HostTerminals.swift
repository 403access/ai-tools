import Foundation

/// A tab open in Terminal.app on the hub host. These are terminal emulator
/// sessions rather than OpenCode PTYs, so the hub mirrors their text and runs
/// commands through macOS automation.
struct HostTerminal: Decodable, Identifiable, Equatable, Sendable {
    /// Stable while the tab stays open, e.g. `ttys001`.
    var id: String
    /// Device path, e.g. `/dev/ttys001`.
    var tty: String
    var app: String
    var title: String
    var busy: Bool
    var processes: [String]
    var window: Int
    var tab: Int

    var processLabel: String {
        processes.last ?? "shell"
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? processLabel : trimmed
    }

    var shortTTY: String {
        (tty as NSString).lastPathComponent
    }

    var locationLabel: String {
        "window \(window) · tab \(tab)"
    }
}

struct HostTerminalDetail: Decodable, Equatable, Sendable {
    var id: String
    var tty: String
    var app: String
    var title: String
    var busy: Bool
    var processes: [String]
    var window: Int
    var tab: Int
    var contents: String
    var history: String?

    var displayText: String {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacingOccurrences(
                    of: "\\s+$",
                    with: "",
                    options: .regularExpression
                )
            }
        // A terminal screen is small; keep a generous cap for unusual tabs.
        return lines.suffix(500).joined(separator: "\n")
    }
}

struct HostTerminalsEnvelope: Decodable {
    let data: [HostTerminal]
}

struct HostTerminalEnvelope: Decodable {
    let data: HostTerminalDetail
}

struct HostTerminalCommandRequest: Encodable {
    var command: String
}

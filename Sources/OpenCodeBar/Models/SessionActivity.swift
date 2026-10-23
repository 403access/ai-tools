import Foundation

/// What a running session is doing right now, reconstructed from the event
/// stream. The panel keeps one of these per active session so the Live list can
/// show the current step instead of just an elapsed timer.
struct SessionActivity: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case starting
        case thinking
        case writing
        case tool
        case waitingForPermission
        case failed
    }

    struct Tool: Equatable, Sendable {
        var callID: String?
        var name: String
        var summary: String?
        /// Event/message status: streaming, running, completed or error.
        var status: String
        var startedAt: Date
        var endedAt: Date?
        var error: String?
    }

    struct Todo: Equatable, Sendable, Identifiable {
        var content: String
        var status: String

        var id: String { content }
        var isDone: Bool { status == "completed" || status == "cancelled" }
        var isActive: Bool { status == "in_progress" }
    }

    var phase: Phase = .starting
    var tool: Tool?
    /// Tail of the current reasoning or response, or the text of a permission
    /// request. The Live row shows its last line.
    var detail: String?
    var todos: [Todo] = []
    var cost: Double?
    var tokens: TokenUsage?
    var stepStartedAt: Date = Date()
    var updatedAt: Date = Date()

    init(stepStartedAt: Date = Date(), now: Date = Date()) {
        self.stepStartedAt = stepStartedAt
        self.updatedAt = now
    }

    // MARK: - Display

    var headline: String {
        switch phase {
        case .starting: return "Working"
        case .thinking: return "Thinking"
        case .writing: return "Writing"
        case .tool: return tool?.name ?? "Working"
        case .waitingForPermission: return "Waiting for approval"
        case .failed: return "Failed"
        }
    }

    /// Friendly verb for the current tool, e.g. "Editing" for `edit`.
    var toolVerb: String {
        guard let tool else { return "Working" }
        let name = tool.name.lowercased()
        guard !name.isEmpty else { return "Working" }
        if tool.status == "completed" { return "Finished" }
        if tool.status == "error" { return "Failed" }
        switch name {
        case "shell", "bash": return "Running"
        case "edit", "patch": return "Editing"
        case "write": return "Writing"
        case "read": return "Reading"
        case "grep", "glob", "list", "find": return "Searching"
        case "webfetch", "websearch": return "Fetching"
        case "task": return "Delegating"
        case "todowrite", "todo": return "Updating todos"
        default: return name
        }
    }

    var icon: String {
        switch phase {
        case .starting: return "hourglass"
        case .thinking: return "brain"
        case .writing: return "text.alignleft"
        case .tool: return "wrench.and.screwdriver.fill"
        case .waitingForPermission: return "lock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    /// The most recent meaningful line of `detail`, ignoring blank lines and
    /// bare Markdown fences.
    var detailLine: String? {
        guard let detail else { return nil }
        let lines = detail
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "```" }
        guard var line = lines.last else { return nil }
        while let first = line.first, "#>*-•".contains(first) {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespaces)
        }
        return line.isEmpty ? nil : line
    }

    var completedTodos: Int { todos.filter(\.isDone).count }
    var totalTodos: Int { todos.count }
    var todoFraction: Double {
        guard totalTodos > 0 else { return 0 }
        return Double(completedTodos) / Double(totalTodos)
    }

    /// The item in progress, or the next one that still needs work.
    var activeTodo: Todo? {
        todos.first(where: \.isActive) ?? todos.first(where: { !$0.isDone })
    }

}

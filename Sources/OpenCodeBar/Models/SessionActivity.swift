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

    // MARK: - Events

    /// Folds one event into the activity. Events unrelated to the visible
    /// state (e.g. step bookkeeping) are ignored.
    mutating func apply(_ event: OpenCodeEvent, directory: String?) {
        guard let data = event.data else { return }
        let now = event.date ?? Date()

        switch event.type {
        case "session.step.started":
            phase = .starting
            tool = nil
            detail = nil
            stepStartedAt = data.started.map(Self.date(millis:)) ?? now

        case "session.reasoning.started":
            phase = .thinking
            tool = nil
            detail = nil

        case "session.reasoning.delta":
            phase = .thinking
            tool = nil
            detail = Self.appended(data.delta, to: detail)

        case "session.reasoning.ended":
            phase = .thinking
            tool = nil
            if let text = data.text { detail = Self.tail(text) }

        case "session.text.started":
            phase = .writing
            tool = nil
            detail = nil

        case "session.text.delta":
            phase = .writing
            tool = nil
            detail = Self.appended(data.delta, to: detail)

        case "session.text.ended":
            phase = .writing
            tool = nil
            if let text = data.text { detail = Self.tail(text) }

        case "session.tool.input.started":
            phase = .tool
            let name = data.name ?? tool?.name ?? "tool"
            tool = Tool(
                callID: data.id,
                name: name,
                summary: nil,
                status: "streaming",
                startedAt: tool?.startedAt ?? now
            )
            detail = nil

        case "session.tool.called":
            phase = .tool
            let name = data.name ?? tool?.name ?? "tool"
            let existing = tool
            tool = Tool(
                callID: data.id ?? existing?.callID,
                name: name,
                summary: ToolInputSummary.text(name: name, input: data.input, directory: directory),
                status: "running",
                startedAt: existing?.startedAt ?? now
            )
            if let todos = Self.todos(from: data.input) {
                self.todos = todos
            }
            detail = nil

        case "session.tool.progress":
            if tool == nil {
                tool = Tool(
                    callID: data.id,
                    name: "tool",
                    summary: nil,
                    status: "running",
                    startedAt: now
                )
            }
            tool?.status = "running"
            phase = .tool

        case "session.tool.success":
            if let existing = tool {
                tool = Tool(
                    callID: existing.callID ?? data.id,
                    name: existing.name,
                    summary: existing.summary,
                    status: "completed",
                    startedAt: existing.startedAt,
                    endedAt: now,
                    error: nil
                )
            }

        case "session.tool.failed":
            phase = .failed
            let message = Self.errorText(data.error) ?? "Tool failed"
            if let existing = tool {
                tool = Tool(
                    callID: existing.callID ?? data.id,
                    name: existing.name,
                    summary: existing.summary,
                    status: "error",
                    startedAt: existing.startedAt,
                    endedAt: now,
                    error: message
                )
            }
            detail = message

        case "session.step.failed":
            phase = .failed
            tool = nil
            detail = Self.errorText(data.error) ?? "The step failed"

        case "permission.asked":
            phase = .waitingForPermission
            tool = nil
            detail = data.permissionDescription ?? "Approval needed"

        case "permission.replied":
            phase = .starting
            detail = nil

        case "session.compaction.started":
            phase = .starting
            tool = nil
            detail = "Compacting context"

        case "session.compaction.ended":
            phase = .starting
            tool = nil
            detail = nil

        case "session.compaction.failed":
            phase = .failed
            tool = nil
            detail = "Context compaction failed"

        case "session.error":
            phase = .failed
            tool = nil
            detail = Self.errorText(data.error) ?? "Session error"

        case "session.usage.updated":
            if let cost = data.cost { self.cost = cost }
            if let tokens = data.tokens { self.tokens = tokens }

        default:
            return
        }

        updatedAt = now
    }

    /// Builds an activity snapshot from the newest messages. Used on launch and
    /// after the event stream reconnects, when there is no event history.
    static func derive(from messages: [SessionMessage], directory: String?, now: Date = Date()) -> SessionActivity? {
        guard !messages.isEmpty else { return nil }

        var activity = SessionActivity(stepStartedAt: now, now: now)

        // A todowrite call carries the complete list, so the newest one wins —
        // including an empty list, which clears prior progress.
        var foundTodoList = false
        for message in messages {
            for part in (message.content ?? []).reversed() {
                guard part.type == "tool",
                      let name = part.name,
                      name == "todowrite" || name == "todo"
                else { continue }
                if let todos = todos(from: part.state?.input) {
                    activity.todos = todos
                    foundTodoList = true
                    break
                }
            }
            if foundTodoList { break }
        }

        guard let message = messages.first(where: { $0.type == "assistant" }) else {
            activity.phase = .starting
            activity.detail = "Waiting for the model"
            if let newest = messages.first {
                activity.stepStartedAt = newest.time.createdDate
                activity.updatedAt = date(millis: newest.time.completed ?? newest.time.streamed ?? newest.time.created)
            }
            return activity
        }

        activity.stepStartedAt = message.time.createdDate
        activity.cost = message.cost
        activity.tokens = message.tokens

        let parts = message.content ?? []
        var latest = message.time.completed ?? message.time.streamed ?? message.time.created
        for part in parts {
            if let millis = part.time?.completed ?? part.time?.created {
                latest = max(latest, millis)
            }
        }
        activity.updatedAt = date(millis: latest)

        guard let part = parts.last else {
            activity.phase = .starting
            activity.detail = "Waiting for the model"
            return activity
        }

        switch part.type {
        case "tool":
            let name = part.name ?? "tool"
            let status = part.state?.status ?? "running"
            let started = part.time?.created.map { date(millis: $0) } ?? message.time.createdDate
            if status == "completed" || status == "error" {
                // The tool is done but the next step has not arrived yet.
                activity.phase = status == "error" ? .failed : .starting
                activity.detail = status == "error" ? (errorText(part.state?.error) ?? "Tool failed") : "Waiting for the model"
                activity.stepStartedAt = part.time?.completed.map { date(millis: $0) } ?? now
            } else {
                activity.phase = .tool
                activity.tool = Tool(
                    callID: part.id,
                    name: name,
                    summary: ToolInputSummary.text(name: name, input: part.state?.input, directory: directory),
                    status: status,
                    startedAt: started
                )
            }

        case "reasoning":
            if message.time.completed == nil {
                activity.phase = .thinking
                activity.detail = tail(part.text)
            } else {
                activity.phase = .starting
                activity.detail = "Waiting for the model"
            }

        case "text":
            if message.time.completed == nil {
                activity.phase = .writing
                activity.detail = tail(part.text)
            } else {
                activity.phase = .starting
                activity.detail = "Waiting for the model"
            }

        default:
            activity.phase = .starting
        }

        return activity
    }

    // MARK: - Helpers

    private static func appended(_ delta: String?, to detail: String?) -> String? {
        guard let delta, !delta.isEmpty else { return detail }
        return tail((detail ?? "") + delta)
    }

    /// Keeps enough text for a readable tail without holding a whole response.
    private static func tail(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let limit = 1_200
        if text.count <= limit { return text }
        return String(text.suffix(limit))
    }

    private static func date(millis: Double) -> Date {
        Date(timeIntervalSince1970: millis / 1000)
    }

    static func errorText(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        if case .object(let fields) = value {
            for key in ["message", "error", "reason", "detail"] {
                if let text = fields[key]?.stringValue, !text.isEmpty { return text }
            }
        }
        let text = value.compactDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func todos(from input: JSONValue?) -> [Todo]? {
        guard case .object(let fields)? = input,
              case .array(let items)? = fields["todos"]
        else { return nil }

        let todos = items.compactMap { item -> Todo? in
            guard case .object(let fields) = item,
                  let content = fields["content"]?.stringValue,
                  !content.isEmpty
            else { return nil }
            return Todo(content: content, status: fields["status"]?.stringValue ?? "pending")
        }
        return todos
    }
}

/// Turns a tool's JSON input into a one-line summary for the Live row.
enum ToolInputSummary {
    static func text(name: String, input: JSONValue?, directory: String?) -> String? {
        guard let input, case .object(let fields) = input else { return nil }
        let lowered = name.lowercased()
        if lowered == "todowrite" || lowered == "todo" { return nil }

        for key in ["command", "description", "filePath", "path", "pattern", "query", "url"] {
            guard let value = fields[key]?.stringValue, !value.isEmpty else { continue }
            return shorten(value, directory: directory)
        }
        return nil
    }

    private static func shorten(_ value: String, directory: String?) -> String {
        var text = value.replacingOccurrences(of: "\n", with: " ")
        if let directory, !directory.isEmpty, text.hasPrefix(directory + "/") {
            text = String(text.dropFirst(directory.count + 1))
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.count > 220 {
            text = String(text.prefix(220)) + "…"
        }
        return text
    }
}

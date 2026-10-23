import Foundation

extension SessionActivity {
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
}

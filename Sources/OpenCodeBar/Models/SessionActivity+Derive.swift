import Foundation

extension SessionActivity {
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
}

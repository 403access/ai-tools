import SwiftUI

/// One-line description of what a running session is doing, with the duration
/// of the current step or tool on the right.
struct ActivityLine: View {
    let activity: SessionActivity
    var now: Date = Date()

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: activity.icon)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 10)

            if activity.phase == .tool {
                Text(activity.toolVerb)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)

                if let summary = activity.tool?.summary {
                    separator
                    Text(summary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(activity.headline)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)

                if let detail = activity.detailLine {
                    separator
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            Text(Fmt.elapsed(since: startedAt, now: elapsedNow))
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
    }

    private var separator: some View {
        Text("·")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
    }

    private var startedAt: Date {
        if activity.phase == .tool, let tool = activity.tool {
            return tool.startedAt
        }
        return activity.stepStartedAt
    }

    /// A finished tool keeps its final duration until the next event arrives,
    /// rather than looking as if it is still running.
    private var elapsedNow: Date {
        if activity.phase == .tool, let endedAt = activity.tool?.endedAt {
            return endedAt
        }
        return now
    }

    private var tint: Color {
        switch activity.phase {
        case .starting: return .secondary
        case .thinking: return Theme.reasoning
        case .writing: return Theme.output
        case .tool: return activity.tool?.status == "completed" ? Theme.accent : Theme.running
        case .waitingForPermission: return Theme.warn
        case .failed: return Theme.danger
        }
    }
}

/// Compact todo progress for a running session: completed count, the item in
/// progress, and a small progress bar.
struct TodoProgressRow: View {
    let activity: SessionActivity

    var body: some View {
        if !activity.todos.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.accent)

                Text("\(activity.completedTodos)/\(activity.totalTodos)")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)

                if let todo = activity.activeTodo {
                    Text(todo.content)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                ProgressView(value: activity.todoFraction)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .tint(Theme.accent)
                    .frame(width: 46)
            }
        }
    }
}

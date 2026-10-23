import SwiftUI

extension SessionDetailView {
    // MARK: - Header

    var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(session.displayTitle)
                .font(.headline)
                .textSelection(.enabled)

            HStack(spacing: 5) {
                Text(project)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                if let model = session.model {
                    Chip(text: model.id)
                }
                if let agent = session.agent, !agent.isEmpty {
                    Chip(text: agent, systemImage: "person.fill", tint: Theme.reasoning)
                }
            }

            HStack(spacing: 12) {
                Label(durationLabel, systemImage: isRunning ? "timer" : "clock")
                Label(Fmt.compact(session.tokens.generated) + " tok", systemImage: "text.word.spacing")
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if isRunning, let activity = store.activity(for: sessionID) {
                Divider().opacity(0.4)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 5) {
                        ActivityLine(activity: activity, now: context.date)
                        TodoProgressRow(activity: activity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 13)
    }

    var durationLabel: String {
        if isRunning {
            return Fmt.elapsed(since: session.time.createdDate)
        }
        return Fmt.elapsed(since: session.time.createdDate, now: session.time.updatedDate)
    }
}

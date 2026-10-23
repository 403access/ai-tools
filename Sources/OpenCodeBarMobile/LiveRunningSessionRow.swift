import SwiftUI

struct RunningSessionRow: View {
    let session: Session
    let project: String
    var activity: SessionActivity?
    var subagents: Int = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 9) {
                PulsingDot(size: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(session.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text(Fmt.elapsed(since: session.time.createdDate, now: context.date))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }

                    if let activity {
                        ActivityLine(activity: activity, now: context.date)
                        if !activity.todos.isEmpty {
                            TodoProgressRow(activity: activity)
                        }
                    } else {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small)
                            Text("Working")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

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
                        if session.cost > 0 {
                            Label(Fmt.usd(session.cost), systemImage: "dollarsign.circle")
                                .foregroundStyle(Theme.accent)
                        }
                        Label(Fmt.compact(session.tokens.generated) + " tok", systemImage: "text.word.spacing")
                        if subagents > 0 {
                            Label("\(subagents)", systemImage: "person.2.fill")
                                .foregroundStyle(Theme.reasoning)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }
            .card(padding: 12)
        }
    }
}

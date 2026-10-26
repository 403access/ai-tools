import SwiftUI

struct RunningRow: View {
    let session: Session
    let project: String
    var activity: SessionActivity?
    var subagents: Int = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 10) {
                PulsingDot(size: 8)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let activity {
                        ActivityLine(activity: activity, now: context.date)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("Working")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(Fmt.elapsed(since: session.time.createdDate, now: context.date))
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                        }
                    }

                    HStack(spacing: 5) {
                        Text(project)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                        if let model = session.model {
                            Chip(text: model.id)
                                .help(model.label)
                        }
                        if let agent = session.agent, !agent.isEmpty {
                            Chip(text: agent, systemImage: "person.fill", tint: Theme.reasoning)
                        }
                        if session.isFork {
                            Chip(text: "Fork", systemImage: "arrow.triangle.branch", tint: Theme.accent)
                        }
                        if subagents > 0 {
                            Chip(
                                text: subagents == 1 ? "1 agent" : "\(subagents) agents",
                                systemImage: "person.2.fill",
                                tint: Theme.reasoning
                            )
                            .help(subagents == 1 ? "1 running subagent" : "\(subagents) running subagents")
                        }
                    }

                    if let activity, !activity.todos.isEmpty {
                        TodoProgressRow(activity: activity)
                    }

                    HStack(spacing: 10) {
                        Label(Fmt.elapsed(since: session.time.createdDate, now: context.date), systemImage: "timer")
                        if session.cost > 0 {
                            Text(Fmt.usd(session.cost))
                                .foregroundStyle(Theme.accent)
                        }
                        Label(Fmt.compact(session.tokens.generated) + " tok", systemImage: "text.word.spacing")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .card()
        }
    }
}

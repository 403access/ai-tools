import SwiftUI

/// One child session in the Subagents tab. Shows live activity for running
/// children and outcome, cost and time for finished ones. Tapping opens the
/// child session, which can have its own subagents.
struct SubagentRow: View {
    let session: Session
    let running: Bool
    let activity: SessionActivity?
    let descendants: Int

    var body: some View {
        if running {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
        } else {
            content(now: Date())
        }
    }

    private func content(now: Date) -> some View {
        HStack(alignment: .top, spacing: 9) {
            indicator
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.tail)

                if running {
                    if let activity {
                        ActivityLine(activity: activity, now: now)
                    } else {
                        Text("Working…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 5) {
                    if let agent = session.agent, !agent.isEmpty {
                        Chip(text: agent, systemImage: "person.fill", tint: Theme.reasoning)
                    }
                    if let model = session.model {
                        Chip(text: model.id)
                            .help(model.label)
                    }
                    if descendants > 0 {
                        Chip(
                            text: descendants == 1 ? "1 agent" : "\(descendants) agents",
                            systemImage: "person.2.fill",
                            tint: Theme.reasoning
                        )
                        .help(descendants == 1 ? "1 running subagent" : "\(descendants) running subagents")
                    }

                    Spacer(minLength: 4)

                    if session.cost > 0 {
                        Text(Fmt.usd(session.cost))
                            .foregroundStyle(Theme.accent)
                    }
                    if running {
                        Text(Fmt.elapsed(since: session.time.createdDate, now: now))
                            .foregroundStyle(Theme.running)
                    } else {
                        Text(Fmt.relative(from: session.time.updatedDate))
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .card(padding: 9)
    }

    @ViewBuilder
    private var indicator: some View {
        if running {
            PulsingDot(size: 7)
        } else {
            Image(systemName: outcomeIcon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(outcomeColor)
                .frame(width: 14, height: 14)
        }
    }

    private var outcomeIcon: String {
        switch session.outcome {
        case "succeeded": return "checkmark.circle.fill"
        case "failed": return "xmark.octagon.fill"
        case "interrupted": return "pause.circle.fill"
        default: return "circle.fill"
        }
    }

    private var outcomeColor: Color {
        switch session.outcome {
        case "succeeded": return Theme.accent
        case "failed": return Theme.danger
        case "interrupted": return Theme.warn
        default: return .secondary
        }
    }
}

import SwiftUI

struct SubagentSessionRow: View {
    let session: Session
    let running: Bool
    var activity: SessionActivity?
    var descendants: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if running {
                PulsingDot(size: 7).padding(.top, 5)
            } else {
                Image(systemName: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if running, let activity {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ActivityLine(activity: activity, now: context.date)
                    }
                } else {
                    HStack(spacing: 5) {
                        if let model = session.model { Chip(text: model.id) }
                        Text(Fmt.relative(from: session.time.updatedDate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    if session.cost > 0 {
                        Text(Fmt.usd(session.cost)).foregroundStyle(Theme.accent)
                    }
                    Text(Fmt.compact(session.tokens.generated) + " tok")
                    if descendants > 0 {
                        Label("\(descendants)", systemImage: "person.2.fill")
                            .foregroundStyle(Theme.reasoning)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .card(padding: 11)
    }
}

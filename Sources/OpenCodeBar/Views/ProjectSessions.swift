import SwiftUI

// MARK: - Recent sessions

struct ProjectSessions: View {
    @EnvironmentObject var state: AppState
    let sessions: [Session]

    private var ordered: [Session] { SessionOrdering.mostRecentFirst(sessions) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ordered) { session in
                Button {
                    state.open(session)
                } label: {
                    ProjectSessionRow(session: session, running: false)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Show conversation and prompts")
                .transition(.recentInsertion)

                if session.id != ordered.last?.id {
                    Divider().opacity(0.35)
                }
            }
        }
        .card(padding: 10)
        .animateRecentInsertion(ids: ordered.map(\.id))
    }
}

struct ProjectSessionRow: View {
    let session: Session
    let running: Bool

    var body: some View {
        HStack(spacing: 6) {
            if running {
                PulsingDot(size: 5)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 5, height: 5)
            }

            Text(session.displayTitle)
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if running {
                Text(Fmt.elapsed(since: session.time.createdDate))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(Theme.running)
            } else {
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
                Text(Fmt.relative(from: session.time.updatedDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

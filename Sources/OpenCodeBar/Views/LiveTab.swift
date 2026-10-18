import SwiftUI

struct LiveTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Running") {
                    Text("\(state.runningSessions.count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(state.runningSessions.isEmpty ? .secondary : Theme.running)
                }

                if state.runningSessions.isEmpty {
                    EmptyState(
                        icon: "moon.zzz.fill",
                        title: "No active sessions",
                        subtitle: "Sessions appear here the moment they start."
                    )
                } else {
                    ForEach(state.runningSessions) { session in
                        RunningRow(session: session, project: state.projectName(for: session))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Recent")

                if state.recentSessions.isEmpty {
                    EmptyState(
                        icon: "clock",
                        title: "No recent sessions",
                        subtitle: "Your session history will show up here."
                    )
                } else {
                    ForEach(state.recentSessions.prefix(20)) { session in
                        RecentRow(session: session, project: state.projectName(for: session))
                    }
                }
            }
        }
    }
}

struct RunningRow: View {
    let session: Session
    let project: String

    @State private var pulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.running.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulsing ? 2.4 : 1)
                    .opacity(pulsing ? 0 : 1)
                Circle().fill(Theme.running).frame(width: 8, height: 8)
            }
            .frame(width: 16, height: 16)
            .padding(.top, 3)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Text(project)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    if let model = session.model {
                        Chip(text: model.id)
                    }
                    if let agent = session.agent, !agent.isEmpty {
                        Chip(text: agent, systemImage: "person.fill", tint: Theme.reasoning)
                    }
                }

                HStack(spacing: 10) {
                    Label(Fmt.elapsed(since: session.time.createdDate), systemImage: "timer")
                    Label(Fmt.compact(session.tokens.generated) + " tok", systemImage: "text.word.spacing")
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .card()
    }
}

struct RecentRow: View {
    let session: Session
    let project: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(project)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    if let model = session.model {
                        Chip(text: model.id)
                    }
                    Text(Fmt.relative(from: session.time.updatedDate))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("free")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(Fmt.compact(session.tokens.generated) + " tok")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .card(padding: 10)
    }
}

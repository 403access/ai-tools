import SwiftUI

struct LiveTab: View {
    @EnvironmentObject var state: AppState
    @State private var showingNewSession = false

    var body: some View {
        let running = state.runningSessions
        let recent = Array(state.recentSessions.prefix(20))

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Running") {
                    HStack(spacing: 7) {
                        Text("\(running.count)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(running.isEmpty ? .secondary : Theme.running)

                        Button {
                            showingNewSession = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .bold))
                                Text("New")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Theme.accent.opacity(0.14))
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .help("Start a new session")
                        .accessibilityLabel("New session")
                    }
                }

                if running.isEmpty {
                    EmptyState(
                        icon: "moon.zzz.fill",
                        title: "No active sessions",
                        subtitle: "Sessions appear here the moment they start."
                    )
                    .transition(.opacity)
                } else {
                    ForEach(running) { session in
                        Button {
                            state.open(session)
                        } label: {
                            RunningRow(
                                session: session,
                                project: state.projectName(for: session),
                                activity: state.activity(for: session.id),
                                subagents: state.activeSubagentCount(for: session.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Show conversation and prompts")
                        .transition(.recentInsertion)
                    }
                }
            }
            .animateRecentInsertion(ids: running.map(\.id))

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Recent")

                if recent.isEmpty {
                    EmptyState(
                        icon: "clock",
                        title: "No recent sessions",
                        subtitle: "Your session history will show up here."
                    )
                    .transition(.opacity)
                } else {
                    ForEach(recent) { session in
                        Button {
                            state.open(session)
                        } label: {
                            RecentRow(session: session, project: state.projectName(for: session))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Show conversation and prompts")
                        .transition(.recentInsertion)
                    }
                }
            }
            .animateRecentInsertion(ids: recent.map(\.id))
        }
        .sheet(isPresented: $showingNewSession) {
            NewSessionSheet()
                .environmentObject(state)
        }
    }
}

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

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 10)
    }
}

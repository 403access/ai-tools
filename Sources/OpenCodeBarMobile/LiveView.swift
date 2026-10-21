import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !settings.isConfigured {
                    ScrollView {
                        SetupPrompt()
                            .padding()
                    }
                } else {
                    content
                }
            }
            .navigationTitle("OpenCode")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionPill(connection: store.connection, activeCount: store.activeCount)
                }
            }
            .refreshable { await store.refreshAll() }
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(sessionID: session.id, fallback: session)
            }
            .task(id: store.lastUpdated) {
                openRequestedSession()
            }
        }
    }

    #if DEBUG
    /// Opens a session on launch for screenshot tooling:
    /// `SIMCTL_CHILD_OPENCODEBAR_OPEN_SESSION=running` or a session id.
    private func openRequestedSession() {
        guard path.isEmpty,
              let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_OPEN_SESSION"]
        else { return }
        if requested == "running" {
            if let first = store.runningSessions.first { path.append(first) }
        } else if let match = store.session(id: requested) {
            path.append(match)
        }
    }
    #else
    private func openRequestedSession() {}
    #endif

    private var content: some View {
        List {
            if case .offline(let reason) = store.connection {
                Section {
                    NoticeRow(icon: "wifi.exclamationmark", message: reason, tint: Theme.warn)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section {
                if store.runningSessions.isEmpty {
                    EmptyState(
                        icon: "moon.zzz.fill",
                        title: "No active sessions",
                        subtitle: "Sessions appear here the moment they start."
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else {
                    ForEach(store.runningSessions) { session in
                        NavigationLink(value: session) {
                            RunningSessionRow(
                                session: session,
                                project: store.projectName(for: session),
                                activity: store.activity(for: session.id),
                                subagents: store.activeSubagentCount(for: session.id)
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
                    }
                }
            } header: {
                HStack {
                    Text("Running")
                    Spacer()
                    Text("\(store.runningSessions.count)")
                        .monospacedDigit()
                        .foregroundStyle(store.runningSessions.isEmpty ? Color.secondary : Theme.running)
                }
            }

            Section {
                if store.recentSessions.isEmpty {
                    EmptyState(
                        icon: "clock",
                        title: "No recent sessions",
                        subtitle: "Your session history will show up here."
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else {
                    ForEach(store.recentSessions.prefix(30)) { session in
                        NavigationLink(value: session) {
                            RecentSessionRow(
                                session: session,
                                project: store.projectName(for: session)
                            )
                        }
                    }
                }
            } header: {
                Text("Recent")
            } footer: {
                if let updated = store.lastUpdated {
                    Text("Updated \(Fmt.relative(from: updated))")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct RunningSessionRow: View {
    let session: Session
    let project: String
    var activity: SessionActivity?
    var subagents: Int = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    PulsingDot(size: 9)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
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
                    }
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
            .padding(.vertical, 3)
        }
    }
}

struct RecentSessionRow: View {
    let session: Session
    let project: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(project)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    if let model = session.model {
                        Chip(text: model.id)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.relative(from: session.time.updatedDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
                Text(Fmt.compact(session.tokens.generated) + " tok")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

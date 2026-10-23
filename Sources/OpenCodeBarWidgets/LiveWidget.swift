import SwiftUI
import WidgetKit

enum WidgetLinks {
    static let live = URL(string: "opencodebar://live")!
    static let usage = URL(string: "opencodebar://usage")!

    static func session(_ id: String) -> URL? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "opencodebar://session/\(encoded)")
    }
}

struct LiveEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct LiveProvider: TimelineProvider {
    func placeholder(in context: Context) -> LiveEntry {
        LiveEntry(date: Date(), snapshot: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (LiveEntry) -> Void) {
        let snapshot = WidgetShared.loadSnapshot() ?? .empty(connection: .connecting)
        completion(LiveEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LiveEntry>) -> Void) {
        Task {
            let snapshot = await WidgetDataLoader.load()
            let entry = LiveEntry(date: Date(), snapshot: snapshot)
            let next = Date().addingTimeInterval(5 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct LiveWidget: Widget {
    let kind = "OpenCodeBarLive"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LiveProvider()) { entry in
            LiveWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Live Sessions")
        .description("See which OpenCode sessions are running and what they are doing.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct LiveWidgetView: View {
    let entry: LiveEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    private var hasData: Bool {
        !snapshot.running.isEmpty || !snapshot.recent.isEmpty
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                small
            case .systemMedium:
                medium
            default:
                large
            }
        }
        .padding(13)
        .widgetURL(WidgetLinks.live)
    }

    // MARK: - Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                WidgetBrand(showsWordmark: false)
                Text("Live")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                WidgetStatusDot(connection: snapshot.connection)
            }

            Spacer(minLength: 4)

            if snapshot.connection == .disabled {
                WidgetEmptyState(
                    icon: "desktopcomputer.and.iphone",
                    title: "Pair your hub",
                    detail: "Open the app to connect to your Mac."
                )
            } else if snapshot.connection == .connecting && !hasData {
                WidgetEmptyState(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Connecting to hub",
                    detail: "The widget refreshes as soon as your Mac answers."
                )
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(snapshot.activeCount)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(snapshot.activeCount > 0 ? Theme.running : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("running")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let first = snapshot.running.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(first.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 4) {
                            Text(first.project)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                            Text(first.startedAt, style: .timer)
                                .font(.system(size: 8.5).monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        if first.activity != nil {
                            Text(activityLine(first))
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 4)
                } else if let recent = snapshot.recent.first {
                    Text("Last: \(recent.title)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 4)
                } else if snapshot.connection == .offline {
                    Text("Hub unreachable")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Text("All quiet")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                Spacer(minLength: 2)
                Text(updatedLabel)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            if snapshot.connection == .disabled {
                WidgetEmptyState(
                    icon: "desktopcomputer.and.iphone",
                    title: "Pair your hub",
                    detail: "Open OpenCodeBar and connect to your Mac to see live sessions here."
                )
            } else if snapshot.connection == .connecting && !hasData {
                WidgetEmptyState(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Connecting to hub",
                    detail: "The widget refreshes as soon as your Mac answers."
                )
            } else if snapshot.running.isEmpty {
                WidgetEmptyState(
                    icon: snapshot.connection == .offline ? "wifi.exclamationmark" : "moon.zzz.fill",
                    title: snapshot.connection == .offline ? "Hub unreachable" : "No active sessions",
                    detail: snapshot.connection == .offline
                        ? snapshot.message
                        : lastSessionLine,
                    tint: snapshot.connection == .offline ? Theme.danger : Theme.accent
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot.running.prefix(2)) { session in
                        row(session, showsActivity: true)
                    }
                }
                Spacer(minLength: 0)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if snapshot.connection == .disabled {
                WidgetEmptyState(
                    icon: "desktopcomputer.and.iphone",
                    title: "Pair your hub",
                    detail: "Open OpenCodeBar and connect to your Mac to see live sessions here."
                )
            } else if snapshot.connection == .connecting && !hasData {
                WidgetEmptyState(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Connecting to hub",
                    detail: "The widget refreshes as soon as your Mac answers."
                )
            } else {
                WidgetSectionLabel(title: "Running", trailing: "\(snapshot.running.count)")

                if snapshot.running.isEmpty {
                    Text(snapshot.connection == .offline ? "Hub unreachable — showing the last snapshot." : "No active sessions")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(snapshot.running.prefix(4)) { session in
                            row(session, showsActivity: true, showsCost: true)
                        }
                    }
                }

                if !snapshot.recent.isEmpty {
                    WidgetSectionLabel(title: "Recent")
                    VStack(spacing: 5) {
                        ForEach(snapshot.recent.prefix(3)) { session in
                            recentRow(session)
                        }
                    }
                }

                Spacer(minLength: 0)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 6) {
            WidgetBrand()
            Text("Live")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let version = snapshot.hubVersion {
                Text("v\(version)")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                WidgetStatusDot(connection: snapshot.connection)
                Text(statusLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func row(
        _ session: WidgetSnapshot.Session,
        showsActivity: Bool,
        showsCost: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Circle()
                .fill(Theme.running)
                .frame(width: 5, height: 5)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(session.project)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)

                    if showsActivity, session.activity != nil {
                        Text(activityLine(session))
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.elapsed(since: session.startedAt))
                    .font(.system(size: 8.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
                if showsCost, session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .font(.system(size: 8.5).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.project)")
    }

    private func recentRow(_ session: WidgetSnapshot.Session) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 9)

            Text(session.title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(session.project)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(Fmt.relative(from: session.updatedAt))
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            WidgetStatusDot(connection: snapshot.connection, size: 5)
            Text(updatedLabel)
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if snapshot.activeCount > 0 {
                Text("\(snapshot.activeCount) running")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Theme.running)
            }
        }
    }

    private var statusLabel: String {
        switch snapshot.connection {
        case .connected: return snapshot.activeCount > 0 ? "\(snapshot.activeCount) running" : "Connected"
        case .connecting: return "Connecting"
        case .offline: return "Offline"
        case .disabled: return "Not configured"
        }
    }

    private var updatedLabel: String {
        "Updated " + Fmt.relative(from: snapshot.generatedAt)
    }

    private var lastSessionLine: String? {
        guard let recent = snapshot.recent.first else { return nil }
        return "Last: \(recent.title) · \(recent.project)"
    }

    private func activityLine(_ session: WidgetSnapshot.Session) -> String {
        guard let activity = session.activity else { return "" }
        guard let detail = session.activityDetail, !detail.isEmpty else { return activity }
        return "\(activity) · \(detail)"
    }
}

#Preview(as: .systemMedium) {
    LiveWidget()
} timeline: {
    LiveEntry(date: .now, snapshot: .placeholder())
    LiveEntry(date: .now, snapshot: .placeholder(connection: .offline))
}

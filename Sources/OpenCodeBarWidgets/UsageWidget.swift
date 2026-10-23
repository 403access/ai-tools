import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = WidgetShared.loadSnapshot() ?? .empty(connection: .connecting)
        completion(UsageEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let snapshot = await WidgetDataLoader.load()
            let entry = UsageEntry(date: Date(), snapshot: snapshot)
            let next = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct UsageWidget: Widget {
    let kind = "OpenCodeBarUsage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Usage")
        .description("Today's steps and spend, plan limits, and the recent activity trend.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var metrics: WidgetSnapshot.Metrics? { snapshot.metrics }

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
        .widgetURL(WidgetLinks.usage)
    }

    // MARK: - Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                WidgetBrand(showsWordmark: false)
                Text("Usage")
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
            } else if let metrics {
                Text(Fmt.grouped(metrics.todaySteps))
                    .font(.system(size: 33, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("steps today")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    Label(Fmt.usd(metrics.cost), systemImage: "dollarsign.circle.fill")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Label("\(metrics.streak)d", systemImage: "flame.fill")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.warn)
                }
                .lineLimit(1)

                if let window = primaryPlanWindow {
                    WidgetPlanLimit(window: window, showsReset: false)
                        .padding(.top, 5)
                } else {
                    Text("\(Fmt.compact(metrics.generatedTokens)) tokens · \(metrics.sessions) sessions")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
            } else {
                WidgetEmptyState(
                    icon: snapshot.connection == .offline ? "wifi.exclamationmark" : "hourglass",
                    title: snapshot.connection == .offline ? "Hub unreachable" : "Waiting for stats",
                    detail: snapshot.connection == .offline ? snapshot.message : "The hub will fill this in after the next sync.",
                    tint: snapshot.connection == .offline ? Theme.danger : Theme.warn
                )
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
                    detail: "Open OpenCodeBar and connect to your Mac to see usage here."
                )
            } else if let metrics {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.running)
                            Text("Today")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(Fmt.grouped(metrics.todaySteps))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("steps")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 4)

                        HStack(spacing: 9) {
                            miniMetric(
                                icon: "dollarsign.circle.fill",
                                tint: Theme.accent,
                                value: Fmt.usd(metrics.cost),
                                label: "cost"
                            )
                            miniMetric(
                                icon: "cpu",
                                tint: Theme.reasoning,
                                value: Fmt.compact(metrics.generatedTokens),
                                label: "tokens"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().opacity(0.35)

                    VStack(alignment: .leading, spacing: 5) {
                        if let usage = snapshot.usage, usage.configured, !usage.windows.isEmpty {
                            ForEach(usage.windows.prefix(3)) { window in
                                WidgetPlanLimit(window: window, showsReset: false)
                            }
                        } else {
                            miniMetric(icon: "flame.fill", tint: Theme.warn, value: "\(metrics.streak)d", label: "streak")
                            miniMetric(icon: "bubble.left.and.bubble.right.fill", tint: Theme.input, value: Fmt.grouped(metrics.prompts), label: "prompts")
                            miniMetric(icon: "wrench.and.screwdriver.fill", tint: Theme.output, value: Fmt.grouped(metrics.toolCalls), label: "tool calls")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
                footer
            } else {
                WidgetEmptyState(
                    icon: snapshot.connection == .offline ? "wifi.exclamationmark" : "hourglass",
                    title: snapshot.connection == .offline ? "Hub unreachable" : "Waiting for stats",
                    detail: snapshot.connection == .offline ? snapshot.message : "The hub will fill this in after the next sync.",
                    tint: snapshot.connection == .offline ? Theme.danger : Theme.warn
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large

    private var large: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if snapshot.connection == .disabled {
                WidgetEmptyState(
                    icon: "desktopcomputer.and.iphone",
                    title: "Pair your hub",
                    detail: "Open OpenCodeBar and connect to your Mac to see usage here."
                )
            } else if let metrics {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ],
                    spacing: 8
                ) {
                    metric(icon: "flame.fill", tint: Theme.warn, label: "Streak", value: "\(metrics.streak)d", caption: "\(metrics.activeDays) active days")
                    metric(icon: "bolt.fill", tint: Theme.running, label: "Today", value: Fmt.grouped(metrics.todaySteps), caption: "steps")
                    metric(icon: "dollarsign.circle.fill", tint: Theme.accent, label: "Cost", value: Fmt.usd(metrics.cost), caption: "all time")
                    metric(icon: "cpu", tint: Theme.reasoning, label: "Tokens", value: Fmt.compact(metrics.generatedTokens), caption: "\(Fmt.compact(metrics.cacheReadTokens)) cached")
                    metric(icon: "bubble.left.and.bubble.right.fill", tint: Theme.input, label: "Prompts", value: Fmt.grouped(metrics.prompts), caption: "\(Fmt.grouped(metrics.sessions)) sessions")
                    metric(icon: "wrench.and.screwdriver.fill", tint: Theme.output, label: "Tools", value: Fmt.grouped(metrics.toolCalls), caption: "\(metrics.subagents) subagents")
                }

                VStack(alignment: .leading, spacing: 5) {
                    WidgetSectionLabel(title: "Steps · 14 days", trailing: Fmt.grouped(metrics.days.reduce(0) { $0 + $1.steps }))
                    WidgetActivityBars(days: metrics.days, height: 28)
                }

                if let usage = snapshot.usage, usage.configured, !usage.windows.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        WidgetSectionLabel(title: "Plan limits")
                        VStack(spacing: 5) {
                            ForEach(usage.windows) { window in
                                WidgetPlanLimit(window: window)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
                footer
            } else {
                WidgetEmptyState(
                    icon: snapshot.connection == .offline ? "wifi.exclamationmark" : "hourglass",
                    title: snapshot.connection == .offline ? "Hub unreachable" : "Waiting for stats",
                    detail: snapshot.connection == .offline ? snapshot.message : "The hub will fill this in after the next sync.",
                    tint: snapshot.connection == .offline ? Theme.danger : Theme.warn
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 6) {
            WidgetBrand()
            Text("Usage")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let version = snapshot.hubVersion {
                Text("v\(version)")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            WidgetStatusDot(connection: snapshot.connection)
        }
    }

    private func metric(
        icon: String,
        tint: Color,
        label: String,
        value: String,
        caption: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func miniMetric(
        icon: String,
        tint: Color,
        value: String,
        label: String
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 7.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var footer: some View {
        HStack(spacing: 4) {
            WidgetStatusDot(connection: snapshot.connection, size: 5)
            Text("Updated " + Fmt.relative(from: snapshot.generatedAt))
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if let note = snapshot.usage?.note, !note.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Theme.warn)
                    .accessibilityLabel(note)
            }
            Text(snapshot.connection.label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    /// The monthly window is the best single-number summary for the small size.
    private var primaryPlanWindow: WidgetSnapshot.PlanWindow? {
        guard let usage = snapshot.usage, usage.configured else { return nil }
        return usage.windows.last
    }
}

#Preview(as: .systemMedium) {
    UsageWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder())
    UsageEntry(date: .now, snapshot: .placeholder(connection: .offline))
}

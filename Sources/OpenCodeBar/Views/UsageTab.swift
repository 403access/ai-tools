import SwiftUI

struct UsageTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let stats = state.stats {
            VStack(alignment: .leading, spacing: 14) {
                if state.statsStale { cachedStatsNotice }

                planLimits

                SectionHeader("Trend")
                UsageTrendCard(stats: stats, sessions: state.history)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    StatTile(
                        icon: "flame.fill",
                        tint: Theme.warn,
                        label: "Streak",
                        value: "\(stats.streak)",
                        caption: "\(stats.activeDays) active days"
                    )
                    StatTile(
                        icon: "bolt.fill",
                        tint: Theme.running,
                        label: "Today",
                        value: Fmt.grouped(state.todaySteps),
                        caption: "steps"
                    )
                    StatTile(
                        icon: "bubble.left.and.bubble.right.fill",
                        tint: Theme.input,
                        label: "Prompts",
                        value: Fmt.grouped(stats.prompts),
                        caption: "\(Fmt.grouped(stats.sessions)) sessions"
                    )
                    StatTile(
                        icon: "dollarsign.circle.fill",
                        tint: Theme.accent,
                        label: "Total cost",
                        value: Fmt.usd(stats.cost),
                        caption: "\(Fmt.compact(Double(stats.steps))) steps"
                    )
                    StatTile(
                        icon: "cpu",
                        tint: Theme.reasoning,
                        label: "Tokens",
                        value: Fmt.compact(stats.tokens.generated),
                        caption: "\(Fmt.compact(stats.tokens.cache.read)) cache read"
                    )
                    StatTile(
                        icon: "wrench.and.screwdriver.fill",
                        tint: Theme.output,
                        label: "Tool calls",
                        value: Fmt.grouped(stats.tools.totals?.calls ?? 0),
                        caption: "\(stats.subagents) subagents"
                    )
                }

                if !state.history.isEmpty {
                    SectionHeader("Project spend")
                    ProjectUsageCard(sessions: state.history, projects: state.projects)
                }

                SectionHeader("Activity")
                HeatmapView(activity: stats.activity)

                SectionHeader("Token mix")
                TokenBreakdown(tokens: stats.tokens)

                if !stats.models.isEmpty {
                    SectionHeader("Models")
                    ModelBreakdown(models: stats.models)
                }

                if let totals = stats.tools.totals {
                    SectionHeader("Tool calls")
                    ToolSummary(totals: totals)

                    if let usage = stats.tools.usage, !usage.isEmpty {
                        SectionHeader("Tools") {
                            Text("\(usage.count)")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        ToolUsageBreakdown(usage: usage)
                    }
                }
            }
            .task { await state.refreshHistory() }
        } else {
            LoadingState(message: state.connection.isConnected ? "Loading usage…" : state.connection.label)
        }
    }

    /// Go plan quota, when a Go key is configured. Mirrors the console's
    /// rolling / weekly / monthly allowances.
    @ViewBuilder
    private var planLimits: some View {
        switch state.goUsage {
        case .unavailable:
            EmptyView()
        case .loading:
            SectionHeader("Plan limits")
            NoticeRow(icon: "gauge.with.dots.needle.33percent", message: "Loading Go limits…", tint: .secondary)
        case .ready(let usage):
            SectionHeader("Plan limits")
            PlanLimitsView(usage: usage)
        case .stale(let usage, let reason):
            SectionHeader("Plan limits")
            PlanLimitsView(
                usage: usage,
                note: "\(clause(reason)) — showing limits from \(label(for: state.goUsageFetchedAt))"
            )
        case .failed(let message):
            SectionHeader("Plan limits")
            NoticeRow(icon: "exclamationmark.triangle.fill", message: message, tint: Theme.warn)
        }
    }

    /// Shown when the local service can't be reached and the tiles below are
    /// the last numbers we saw.
    private var cachedStatsNotice: some View {
        NoticeRow(
            icon: "clock.arrow.circlepath",
            message: "Can't reach the service — showing usage from \(lastUpdatedLabel)",
            tint: Theme.warn
        )
    }

    private var lastUpdatedLabel: String { label(for: state.statsFetchedAt) }

    private func label(for date: Date?) -> String {
        guard let date else { return "earlier" }
        return Fmt.relative(from: date)
    }

    /// Error messages arrive as full sentences; this drops the trailing period
    /// so they can lead into the "— showing …" clause.
    private func clause(_ reason: String) -> String {
        var trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }
}

/// Three progress rows for the Go subscription windows.
struct PlanLimitsView: View {
    let usage: GoUsage
    /// Optional caveat rendered inside the card, used when the numbers are
    /// stale but still worth showing.
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(usage.ordered, id: \.label) { item in
                PlanLimitRow(label: item.label, window: item.window)
            }

            if let note {
                Divider().opacity(0.5)
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.warn)
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .card()
    }
}

struct PlanLimitRow: View {
    let label: String
    let window: GoUsage.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                if window.isLimited {
                    Chip(text: "rate limited", systemImage: "exclamationmark.triangle.fill", tint: Theme.danger)
                }
                Spacer(minLength: 6)
                if let reset = window.resetDate {
                    Text("resets in \(Fmt.countdown(to: reset))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text("\(Int(window.used.rounded()))% used")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(geo.size.width * CGFloat(window.used / 100), 3))
                }
            }
            .frame(height: 5)
        }
    }

    private var tint: Color {
        if window.isLimited || window.used >= 90 { return Theme.danger }
        if window.used >= 75 { return Theme.warn }
        return Theme.accent
    }
}

/// Compact notice used for plan-limit and cache states.
struct NoticeRow: View {
    let icon: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }
}

struct ModelBreakdown: View {
    let models: [Stats.ModelUsage]

    var body: some View {
        let top = Array(models.sorted { $0.steps > $1.steps }.prefix(6))
        let maxSteps = max(top.map(\.steps).max() ?? 1, 1)

        VStack(spacing: 10) {
            ForEach(top) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.model.label)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text("\(Fmt.grouped(item.steps)) steps")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if item.cost > 0 {
                            Text(Fmt.usd(item.cost))
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule()
                                .fill(Theme.accent.opacity(0.8))
                                .frame(width: max(geo.size.width * CGFloat(Double(item.steps) / Double(maxSteps)), 3))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .card()
    }
}

struct ToolSummary: View {
    let totals: Stats.ToolTotals

    var body: some View {
        let total = max(totals.calls, 1)
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                metric("Calls", Fmt.grouped(totals.calls), .primary)
                metric("Succeeded", Fmt.grouped(totals.succeeded), Theme.accent)
                metric("Failed", Fmt.grouped(totals.failed), totals.failed > 0 ? Theme.danger : .secondary)
                metric("Unfinished", Fmt.grouped(totals.unfinished), totals.unfinished > 0 ? Theme.warn : .secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * CGFloat(Double(totals.succeeded) / Double(total)))
                    Rectangle()
                        .fill(Theme.danger)
                        .frame(width: geo.size.width * CGFloat(Double(totals.failed) / Double(total)))
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
        }
        .card()
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AppState.Connection {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

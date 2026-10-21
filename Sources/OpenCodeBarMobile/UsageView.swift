import SwiftUI
import UIKit

struct UsageView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore

    var body: some View {
        NavigationStack {
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
            .mobileScreenBackground()
            .navigationTitle("Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionPill(connection: store.connection, activeCount: store.activeCount)
                }
            }
            .refreshable {
                await store.refreshStats(force: true)
                await store.refreshHistory(force: true)
                await store.refreshUsage()
            }
            .task {
                await store.refreshStats()
                await store.refreshHistory()
                await store.refreshUsage()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let stats = store.stats {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.statsStale {
                        NoticeRow(
                            icon: "clock.arrow.circlepath",
                            message: "Hub is offline — showing cached usage.",
                            tint: Theme.warn
                        )
                    }

                    planLimits

                    SectionHeader("Trend")
                    UsageTrendCard(stats: stats, sessions: store.history)

                    statGrid(stats)

                    if !store.history.isEmpty {
                        TopProjectsCard(sessions: store.history, projects: store.projects)
                    }

                    SectionHeader("Activity")
                    HeatmapView(activity: stats.activity, weeks: 18)

                    SectionHeader("Token mix")
                    TokenBreakdown(tokens: stats.tokens)

                    if !stats.models.isEmpty {
                        SectionHeader("Models")
                        ModelBreakdownCard(models: stats.models)
                    }

                    if let totals = stats.tools.totals {
                        SectionHeader("Tool calls")
                        ToolSummaryCard(totals: totals, mode: stats.tools.mode)

                        if let usage = stats.tools.usage, !usage.isEmpty {
                            SectionHeader("Tools") {
                                Text("\(usage.count)")
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ToolUsageBreakdown(usage: usage)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } else {
            ScrollView {
                LoadingState(message: store.connection.isConnected ? "Loading usage…" : store.connection.label)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var planLimits: some View {
        if let usage = store.usage, usage.configured {
            if let data = usage.data {
                SectionHeader("Plan limits")
                PlanLimitsCard(usage: data, note: usageNote(usage))
            } else if let error = usage.error {
                SectionHeader("Plan limits")
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
            }
        }
    }

    private func usageNote(_ usage: HubUsageResponse) -> String? {
        guard usage.stale == true, let error = usage.error, !error.isEmpty else { return nil }
        var reason = error.trimmingCharacters(in: .whitespacesAndNewlines)
        while reason.hasSuffix(".") { reason.removeLast() }
        let when = usage.fetchedDate.map { Fmt.relative(from: $0) } ?? "earlier"
        return "\(reason) — showing limits from \(when)"
    }

    private func statGrid(_ stats: Stats) -> some View {
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
                value: Fmt.grouped(store.todaySteps),
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
    }
}

struct PlanLimitsCard: View {
    let usage: GoUsage
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(usage.ordered, id: \.label) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(item.label)
                            .font(.subheadline.weight(.semibold))
                        if item.window.isLimited {
                            Chip(text: "limited", tint: Theme.danger)
                        }
                        Spacer()
                        if let reset = item.window.resetDate {
                            Text("resets in \(Fmt.countdown(to: reset))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Int(item.window.used))% used")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(tint(for: item.window))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule()
                                .fill(tint(for: item.window))
                                .frame(width: max(geo.size.width * CGFloat(item.window.used / 100), item.window.used > 0 ? 4 : 0))
                        }
                    }
                    .frame(height: 6)
                }
            }

            if let note {
                Divider().opacity(0.5)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .card()
    }

    private func tint(for window: GoUsage.Window) -> Color {
        if window.isLimited { return Theme.danger }
        if window.used >= 80 { return Theme.warn }
        return Theme.accent
    }
}

struct ToolSummaryCard: View {
    let totals: Stats.ToolTotals
    let mode: String

    private var successRate: Double {
        guard totals.calls > 0 else { return 0 }
        return Double(totals.succeeded) / Double(totals.calls)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(Fmt.grouped(totals.calls)) calls")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(mode.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    if totals.succeeded > 0 {
                        Rectangle().fill(Theme.accent)
                            .frame(width: geo.size.width * CGFloat(totals.succeeded) / CGFloat(max(totals.calls, 1)))
                    }
                    if totals.failed > 0 {
                        Rectangle().fill(Theme.danger)
                            .frame(width: geo.size.width * CGFloat(totals.failed) / CGFloat(max(totals.calls, 1)))
                    }
                    if totals.unfinished > 0 {
                        Rectangle().fill(Theme.warn)
                            .frame(width: geo.size.width * CGFloat(totals.unfinished) / CGFloat(max(totals.calls, 1)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)

            HStack(spacing: 12) {
                legend("Succeeded", value: totals.succeeded, color: Theme.accent)
                legend("Failed", value: totals.failed, color: Theme.danger)
                legend("Unfinished", value: totals.unfinished, color: Theme.warn)
                Spacer()
                Text("\(Int(successRate * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
        }
        .card()
    }

    private func legend(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(label) \(Fmt.grouped(value))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

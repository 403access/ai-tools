import SwiftUI

/// Usage dashboard, split into pages so the panel does not become one long
/// scroll. The section picker and the Go plan strip stay pinned above the
/// scrolling page, since quota is the one number worth checking on every visit.
struct UsageTab: View {
    @EnvironmentObject var state: AppState

    /// Plan limits start as a compact gauge row and expand to the full bars
    /// with reset countdowns on demand.
    @State private var quotaExpanded = false

    /// `nil` shows every tool type; otherwise the Tools page keeps only the
    /// selected category.
    @State private var toolCategory: ToolCategory?

    /// Persisted so the chosen representation survives tab switches and
    /// relaunches.
    @AppStorage("usage.toolVisualization") private var toolVisualization: ToolVisualization = .list

    private let topAnchor = "usage-top"

    var body: some View {
        if let stats = state.stats {
            VStack(alignment: .leading, spacing: 10) {
                if state.statsStale { cachedStatsNotice }

                modePicker

                planLimits

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Color.clear.frame(height: 1).id(topAnchor)

                            switch state.usageMode {
                            case .overview:
                                overview(stats)
                            case .activity:
                                activity(stats)
                            case .breakdown:
                                breakdown(stats)
                            case .tools:
                                tools(stats)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                    }
                    .frame(maxHeight: .infinity)
                    .onChange(of: state.usageMode) { _, _ in
                        proxy.scrollTo(topAnchor, anchor: .top)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task { await state.refreshHistory() }
        } else {
            ScrollView {
                if state.isInitialLoading {
                    UsageSkeleton()
                } else {
                    LoadingState(message: state.connection.isConnected ? "Loading usage…" : state.connection.label)
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("Usage section", selection: $state.usageMode) {
            ForEach(AppState.UsageMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.icon)
                    .labelStyle(.titleAndIcon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .help("Switch between usage sections")
    }

    // MARK: - Pages

    private func overview(_ stats: Stats) -> some View {
        Group {
            SectionHeader("At a glance")
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
                    caption: "\(Fmt.compact(stats.tokens.cache.read)) cache read",
                    action: { state.usageMode = .breakdown },
                    showsDisclosure: true
                )
                StatTile(
                    icon: "wrench.and.screwdriver.fill",
                    tint: Theme.output,
                    label: "Tool calls",
                    value: Fmt.grouped(stats.tools.totals?.calls ?? 0),
                    caption: "\(stats.subagents) subagents",
                    action: { state.usageMode = .tools },
                    showsDisclosure: true
                )
            }

            SectionHeader("Trend")
            UsageTrendCard(stats: stats, sessions: state.history)
        }
    }

    private func activity(_ stats: Stats) -> some View {
        Group {
            SectionHeader("Activity")
            HeatmapView(activity: stats.activity)

            if !state.history.isEmpty {
                SectionHeader("Project spend")
                ProjectUsageCard(sessions: state.history, projects: state.projects)
            }
        }
    }

    private func breakdown(_ stats: Stats) -> some View {
        Group {
            SectionHeader("Token mix")
            TokenBreakdown(tokens: stats.tokens)

            if stats.models.isEmpty {
                SectionHeader("Models")
                NoticeRow(icon: "cpu", message: "No model usage recorded yet.", tint: .secondary)
            } else {
                SectionHeader("Models") {
                    Text("\(stats.models.count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ModelBreakdown(models: stats.models)
            }
        }
    }

    private func tools(_ stats: Stats) -> some View {
        Group {
            if let totals = stats.tools.totals {
                SectionHeader("Tool calls")
                ToolSummary(totals: totals)

                if let usage = stats.tools.usage, !usage.isEmpty {
                    let filtered = filteredTools(usage)
                    SectionHeader("Tools") {
                        Text("\(filtered.count)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ToolCategoryFilter(usage: usage, selection: $toolCategory)
                    ToolVisualizationPicker(selection: $toolVisualization)
                        .controlSize(.small)
                    if filtered.isEmpty {
                        NoticeRow(
                            icon: "line.3.horizontal.decrease.circle",
                            message: "No \(toolCategory?.title ?? "matching") tool calls.",
                            tint: .secondary
                        )
                    } else {
                        ToolVisualizationView(usage: filtered, style: toolVisualization)
                    }
                }
            } else {
                SectionHeader("Tool calls")
                NoticeRow(
                    icon: "wrench.and.screwdriver",
                    message: "No tool calls recorded yet.",
                    tint: .secondary
                )
            }
        }
    }

    private func filteredTools(_ usage: [Stats.ToolUsage]) -> [Stats.ToolUsage] {
        guard let toolCategory else { return usage }
        return usage.filter { $0.category == toolCategory }
    }

    // MARK: - Plan limits

    /// Go plan quota, when a Go key is configured. Mirrors the console's
    /// rolling / weekly / monthly allowances and stays visible on every page.
    @ViewBuilder
    private var planLimits: some View {
        switch state.goUsage {
        case .unavailable:
            EmptyView()
        case .loading:
            NoticeRow(icon: "gauge.with.dots.needle.33percent", message: "Loading Go limits…", tint: .secondary)
        case .ready(let usage):
            PlanLimitsStrip(usage: usage, isExpanded: $quotaExpanded)
        case .stale(let usage, let reason):
            PlanLimitsStrip(
                usage: usage,
                note: "\(clause(reason)) — showing limits from \(label(for: state.goUsageFetchedAt))",
                isExpanded: $quotaExpanded
            )
        case .failed(let message):
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

/// Pinned quota summary for the Go subscription. Collapsed, it shows one compact
/// gauge per window; expanded, it adds the reset countdowns and any stale-data
/// note. Tapping the header toggles the two presentations.
struct PlanLimitsStrip: View {
    let usage: GoUsage
    var note: String?
    @Binding var isExpanded: Bool

    private var isLimited: Bool { usage.ordered.contains { $0.window.isLimited } }

    /// Soonest reset across the configured windows, shown in the collapsed
    /// header so the pinned strip still answers "when does this roll over?".
    private var nextReset: Date? {
        usage.ordered.compactMap(\.window.resetDate).min()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if usage.ordered.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("No Go limits reported yet.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                if let note { noteRow(note) }
            } else if isExpanded {
                VStack(spacing: 10) {
                    ForEach(usage.ordered, id: \.label) { item in
                        PlanLimitRow(label: item.label, window: item.window)
                    }
                }

                if let note { noteRow(note) }
            } else {
                HStack(spacing: 12) {
                    ForEach(usage.ordered, id: \.label) { item in
                        compactGauge(item.label, window: item.window)
                    }
                }
            }
        }
        .card(padding: 10)
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("PLAN LIMITS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                if isLimited {
                    Chip(text: "rate limited", systemImage: "exclamationmark.triangle.fill", tint: Theme.danger)
                } else if note != nil {
                    Chip(text: "stale", systemImage: "clock.arrow.circlepath", tint: Theme.warn)
                }

                Spacer(minLength: 4)

                if !isExpanded, let nextReset {
                    Text("next reset in \(Fmt.countdown(to: nextReset))")
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide reset times" : "Show reset times")
    }

    private func compactGauge(_ label: String, window: GoUsage.Window) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(Int(window.used.rounded()))%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint(for: window))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(tint(for: window))
                        .frame(width: max(geo.size.width * CGFloat(window.used / 100), 2))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(Int(window.used.rounded())) percent used")
    }

    private func noteRow(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
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

    private func tint(for window: GoUsage.Window) -> Color {
        if window.isLimited || window.used >= 90 { return Theme.danger }
        if window.used >= 75 { return Theme.warn }
        return Theme.accent
    }
}

/// One full quota row with reset countdown, used when the pinned strip is
/// expanded.
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

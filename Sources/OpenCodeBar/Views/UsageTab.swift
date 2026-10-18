import SwiftUI

struct UsageTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let stats = state.stats {
            VStack(alignment: .leading, spacing: 14) {
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
                }
            }
        } else {
            LoadingState(message: state.connection.isConnected ? "Loading usage…" : state.connection.label)
        }
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

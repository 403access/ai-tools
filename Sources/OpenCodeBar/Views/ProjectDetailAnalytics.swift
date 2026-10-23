import SwiftUI

// MARK: - Scoped analytics

struct ProjectStats: View {
    let stats: Stats

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            StatTile(
                icon: "bolt.fill",
                tint: Theme.running,
                label: "Steps",
                value: Fmt.grouped(stats.steps),
                caption: "\(Fmt.grouped(stats.prompts)) prompts"
            )
            StatTile(
                icon: "dollarsign.circle.fill",
                tint: Theme.accent,
                label: "Cost",
                value: Fmt.usd(stats.cost),
                caption: "\(Fmt.grouped(stats.sessions)) sessions"
            )
            StatTile(
                icon: "wrench.and.screwdriver.fill",
                tint: Theme.output,
                label: "Tool calls",
                value: Fmt.grouped(stats.tools.totals?.calls ?? 0),
                caption: "\(Fmt.grouped(stats.tools.totals?.succeeded ?? 0)) succeeded"
            )
            StatTile(
                icon: "xmark.octagon.fill",
                tint: (stats.tools.totals?.failed ?? 0) > 0 ? Theme.danger : .secondary,
                label: "Failures",
                value: Fmt.grouped(stats.tools.totals?.failed ?? 0),
                caption: "\(Fmt.grouped(stats.tools.totals?.unfinished ?? 0)) unfinished"
            )
            StatTile(
                icon: "cpu",
                tint: Theme.reasoning,
                label: "Tokens",
                value: Fmt.compact(stats.tokens.generated),
                caption: "\(Fmt.compact(stats.tokens.cache.read)) cache read"
            )
            StatTile(
                icon: "flame.fill",
                tint: Theme.warn,
                label: "Streak",
                value: "\(stats.streak)",
                caption: "\(stats.activeDays) active days"
            )
        }
    }
}

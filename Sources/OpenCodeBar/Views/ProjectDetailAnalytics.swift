import SwiftUI

// MARK: - Scoped analytics

/// Compact six-metric summary shown on a project's Overview tab. One card with
/// two rows of three keeps the whole grid to about half the height of six
/// separate tiles, so recent sessions stay above the fold in the panel.
struct ProjectStats: View {
    let stats: Stats

    private var failed: Int { stats.tools.totals?.failed ?? 0 }
    private var unfinished: Int { stats.tools.totals?.unfinished ?? 0 }

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                metric(
                    icon: "bolt.fill",
                    tint: Theme.running,
                    label: "Steps",
                    value: Fmt.grouped(stats.steps),
                    caption: "\(Fmt.grouped(stats.prompts)) prompts"
                )
                metric(
                    icon: "dollarsign.circle.fill",
                    tint: Theme.accent,
                    label: "Cost",
                    value: Fmt.usd(stats.cost),
                    caption: "\(Fmt.grouped(stats.sessions)) sessions"
                )
                metric(
                    icon: "wrench.and.screwdriver.fill",
                    tint: Theme.output,
                    label: "Tool calls",
                    value: Fmt.grouped(stats.tools.totals?.calls ?? 0),
                    caption: "\(Fmt.grouped(stats.tools.totals?.succeeded ?? 0)) succeeded"
                )
            }

            Divider().opacity(0.35)

            HStack(alignment: .top, spacing: 8) {
                metric(
                    icon: "xmark.octagon.fill",
                    tint: failed > 0 ? Theme.danger : .secondary,
                    label: "Failures",
                    value: Fmt.grouped(failed),
                    caption: "\(Fmt.grouped(unfinished)) unfinished"
                )
                metric(
                    icon: "cpu",
                    tint: Theme.reasoning,
                    label: "Tokens",
                    value: Fmt.compact(stats.tokens.generated),
                    caption: "\(Fmt.compact(stats.tokens.cache.read)) cache read"
                )
                metric(
                    icon: "flame.fill",
                    tint: Theme.warn,
                    label: "Streak",
                    value: "\(stats.streak)",
                    caption: "\(stats.activeDays) active days"
                )
            }
        }
        .card(padding: 10)
    }

    private func metric(
        icon: String,
        tint: Color,
        label: String,
        value: String,
        caption: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(caption)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

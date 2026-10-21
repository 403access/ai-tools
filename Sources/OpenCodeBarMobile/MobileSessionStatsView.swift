import SwiftUI

/// Mobile stats tab: activity, tool reliability, failures, and file impact for
/// one session.
struct MobileSessionStatsView: View {
    let stats: SessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    icon: "wrench.and.screwdriver.fill",
                    tint: Theme.output,
                    label: "Tool calls",
                    value: Fmt.grouped(stats.totals.calls),
                    caption: "\(Fmt.grouped(stats.totals.failed)) failed"
                )
                StatTile(
                    icon: "plus.forwardslash.minus",
                    tint: Theme.accent,
                    label: "Files",
                    value: Fmt.grouped(stats.files.files),
                    caption: "+\(Fmt.grouped(stats.files.additions)) −\(Fmt.grouped(stats.files.deletions))"
                )
                StatTile(
                    icon: "clock",
                    tint: Theme.reasoning,
                    label: "Duration",
                    value: Fmt.duration(milliseconds: stats.time.duration),
                    caption: "\(Fmt.grouped(stats.subagents)) subagents"
                )
            }

            if let totals = stats.tools.totals {
                SectionHeader("Reliability") {
                    if let rate = totals.successRate {
                        Text("\(Int((rate * 100).rounded()))% success")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(successTint(rate))
                    }
                }
                ToolSummaryCard(totals: totals, mode: stats.tools.mode)
            }

            if let usage = stats.tools.usage, !usage.isEmpty {
                SectionHeader("Tools") {
                    Text("\(usage.count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ToolUsageBreakdown(usage: usage)
            }

            if !stats.failures.isEmpty {
                SectionHeader("Recent failures") {
                    Text("\(stats.failures.count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.danger)
                }
                ToolFailureList(failures: stats.failures)
            }

            SectionHeader("Token mix")
            TokenBreakdown(tokens: stats.tokens)

            if !stats.complete {
                NoticeRow(
                    icon: "clock.arrow.circlepath",
                    message: "Some earlier messages aren't cached yet, so these totals cover the history loaded so far.",
                    tint: Theme.warn
                )
            }
        }
    }

    private func successTint(_ rate: Double) -> Color {
        if rate >= 0.98 { return Theme.accent }
        if rate >= 0.90 { return Theme.warn }
        return Theme.danger
    }
}

import Charts
import SwiftUI

/// Metric plotted by `UsageTrendCard`.
enum UsageMetric: String, CaseIterable, Identifiable {
    case steps
    case cost
    case tokens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .cost: return "Cost"
        case .tokens: return "Tokens"
        }
    }

    var icon: String {
        switch self {
        case .steps: return "bolt.fill"
        case .cost: return "dollarsign.circle.fill"
        case .tokens: return "cpu"
        }
    }

    var color: Color {
        switch self {
        case .steps: return Theme.running
        case .cost: return Theme.accent
        case .tokens: return Theme.reasoning
        }
    }

    func value(_ point: DailyUsage) -> Double {
        switch self {
        case .steps: return Double(point.steps)
        case .cost: return point.cost
        case .tokens: return point.tokens
        }
    }

    /// Value format used in the summary row.
    func format(_ value: Double) -> String {
        switch self {
        case .steps: return Fmt.grouped(Int(value.rounded()))
        case .cost: return Fmt.usd(value)
        case .tokens: return Fmt.compact(value)
        }
    }

    /// Short format used for the chart's Y axis.
    func axisLabel(_ value: Double) -> String {
        switch self {
        case .steps, .tokens: return Fmt.compact(value)
        case .cost: return Fmt.usd(value)
        }
    }
}

/// Daily trend chart shared by the global Usage tab and project detail pages.
/// Steps come from the stats API; cost and tokens are grouped from sessions.
struct UsageTrendCard: View {
    let stats: Stats?
    let sessions: [Session]

    @State private var metric: UsageMetric = .steps
    @State private var range: UsageRange = .month

    private var points: [DailyUsage] {
        UsageSeries.build(stats: stats, sessions: sessions, range: range)
    }

    private var hasData: Bool {
        points.contains { metric.value($0) > 0 }
    }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: 8) {
            header

            if hasData {
                chart(points)
                summary(points)
            } else {
                emptyState
            }
        }
        .card()
        .animation(.easeInOut(duration: 0.16), value: metric)
        .animation(.easeInOut(duration: 0.16), value: range)
    }

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(UsageMetric.allCases) { option in
                Button {
                    metric = option
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: option.icon)
                            .font(.system(size: 8, weight: .bold))
                        Text(option.title)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(metric == option ? option.color : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            metric == option
                                ? option.color.opacity(0.15)
                                : Color.clear
                        )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Plot \(option.title.lowercased()) per day")
            }

            Spacer(minLength: 4)

            Menu {
                ForEach(UsageRange.allCases) { option in
                    Button {
                        range = option
                    } label: {
                        if option == range {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(range.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Chart window")
        }
    }

    private func chart(_ points: [DailyUsage]) -> some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value(metric.title, metric.value(point))
            )
            .foregroundStyle(metric.color.opacity(0.88))
            .cornerRadius(2)
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Fmt.shortDateFormatter.string(from: date))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Color.primary.opacity(0.12))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(metric.axisLabel(number))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .frame(height: 104)
    }

    private func summary(_ points: [DailyUsage]) -> some View {
        let total = points.reduce(0) { $0 + metric.value($1) }
        let average = points.isEmpty ? 0 : total / Double(points.count)
        let peak = points.max { metric.value($0) < metric.value($1) }

        return HStack(spacing: 12) {
            summaryItem("Total", metric.format(total))
            summaryItem("Daily avg", metric.format(average))
            if let peak, metric.value(peak) > 0 {
                summaryItem(
                    "Peak · \(Fmt.shortDateFormatter.string(from: peak.date))",
                    metric.format(metric.value(peak))
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 7) {
            Image(systemName: "chart.bar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("No \(metric.title.lowercased()) activity in this range.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(height: 72)
    }
}

/// Global comparison of spend by project. Only shown on the Usage tab, where
/// the full session history is available.
struct ProjectUsageCard: View {
    let sessions: [Session]
    let projects: [String: Project]

    @State private var range: UsageRange = .month

    private var rows: [ProjectUsage] {
        UsageSeries.projects(sessions: sessions, projects: projects, range: range)
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Top projects by cost")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Menu {
                    ForEach(UsageRange.allCases) { option in
                        Button {
                            range = option
                        } label: {
                            if option == range {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(range.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Chart window")
            }

            if rows.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("No project spend in this range.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(height: 72)
            } else {
                Chart(rows) { row in
                    BarMark(
                        x: .value("Cost", row.cost),
                        y: .value("Project", row.name)
                    )
                    .foregroundStyle(Theme.accent.opacity(0.85))
                    .cornerRadius(2)
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.primary.opacity(0.12))
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(Fmt.usd(cost))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .chartPlotStyle { plot in
                    plot.background(Color.clear)
                }
                .frame(height: CGFloat(rows.count) * 22 + 10)
            }
        }
        .card()
        .animation(.easeInOut(duration: 0.16), value: range)
    }
}

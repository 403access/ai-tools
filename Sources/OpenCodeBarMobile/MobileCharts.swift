import Charts
import SwiftUI

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
        case .steps: return "square.stack.3d.up.fill"
        case .cost: return "dollarsign.circle.fill"
        case .tokens: return "text.word.spacing"
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

    func label(_ value: Double) -> String {
        switch self {
        case .cost: return Fmt.usd(value)
        case .steps, .tokens: return Fmt.compact(value)
        }
    }
}

/// Interactive daily trend used by the Usage and project detail screens.
struct UsageTrendCard: View {
    let stats: Stats?
    let sessions: [Session]
    @State private var metric: UsageMetric = .steps
    @State private var range: UsageRange = .month

    private var points: [DailyUsage] {
        UsageSeries.build(stats: stats, sessions: sessions, range: range)
    }

    private var total: Double {
        points.reduce(0) { $0 + metric.value($1) }
    }

    private var peak: Double {
        points.map(metric.value).max() ?? 0
    }

    private var average: Double {
        guard !points.isEmpty else { return 0 }
        return total / Double(points.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Metric", selection: $metric) {
                ForEach(UsageMetric.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("\(points.count) days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
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
                    Label(range.rawValue, systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if points.isEmpty {
                Text("No activity in this window yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value(metric.title, metric.value(point))
                    )
                    .foregroundStyle(metric.color.gradient)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(metric.label(number))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 165)

                HStack(spacing: 0) {
                    summaryItem("Total", metric.label(total))
                    Divider().frame(height: 22)
                    summaryItem("Daily avg", metric.label(average))
                    Divider().frame(height: 22)
                    summaryItem("Peak", metric.label(peak))
                }
            }
        }
        .card()
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}

/// Top projects by spend inside a range, used on the Usage tab.
struct TopProjectsCard: View {
    let sessions: [Session]
    let projects: [String: Project]
    @State private var range: UsageRange = .month

    private var entries: [ProjectUsage] {
        UsageSeries.projects(sessions: sessions, projects: projects, range: range, limit: 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Top projects")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(UsageRange.allCases) { option in
                        Button(option.rawValue) { range = option }
                    }
                } label: {
                    Label(range.rawValue, systemImage: "calendar")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if entries.isEmpty {
                Text("No spend in this window.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let maxCost = entries.map(\.cost).max() ?? 1
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(Fmt.usd(entry.cost))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06))
                                Capsule()
                                    .fill(Theme.accent.opacity(0.65))
                                    .frame(width: max(geo.size.width * CGFloat(entry.cost / maxCost), 3))
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
        .card()
    }
}

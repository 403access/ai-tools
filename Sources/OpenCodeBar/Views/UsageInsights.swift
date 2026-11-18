import Charts
import SwiftUI

/// Overall usage patterns for the selected window: spend and tokens per
/// provider, per project, by weekday, and by hour of day. Kept separate from
/// the existing Usage pages so the compact panel stays scannable while the
/// desktop window can show the whole picture.
struct UsageInsightsView: View {
    let stats: Stats
    let sessions: [Session]
    let projects: [String: Project]
    /// Content width, used to pick a two-column or stacked layout. Zero means
    /// the caller did not measure a width yet; stacking is the safe default.
    var availableWidth: CGFloat = 0

    @AppStorage("usage.insights.range") private var rangeRaw = UsageRange.month.rawValue
    @AppStorage("usage.insights.weekdayMetric") private var weekdayMetricRaw = WeekdayMetric.steps.rawValue

    private var range: UsageRange { UsageRange(rawValue: rangeRaw) ?? .month }

    private var weekdayMetric: WeekdayMetric {
        WeekdayMetric(rawValue: weekdayMetricRaw) ?? .steps
    }

    private var rangeBinding: Binding<UsageRange> {
        Binding(
            get: { range },
            set: { rangeRaw = $0.rawValue }
        )
    }

    private var totals: UsagePeriodTotals {
        UsageInsights.totals(stats: stats, sessions: sessions, range: range)
    }

    private var previousTotals: UsagePeriodTotals? {
        UsageInsights.previousTotals(stats: stats, sessions: sessions, range: range)
    }

    private var providers: [ProviderUsage] {
        UsageInsights.providers(sessions: sessions, range: range)
    }

    private var projectRows: [ProjectInsight] {
        UsageInsights.projects(sessions: sessions, projects: projects, range: range)
    }

    private var weekdays: [WeekdayUsage] {
        UsageInsights.weekdays(stats: stats, sessions: sessions, range: range)
    }

    private var hours: [HourUsage] {
        UsageInsights.hours(sessions: sessions, range: range)
    }

    private var punchCard: UsagePunchCard {
        UsageInsights.punchCard(sessions: sessions, range: range)
    }

    private var isTwoColumn: Bool { availableWidth >= 760 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pulseCard

            if isTwoColumn {
                HStack(alignment: .top, spacing: 14) {
                    providersCard
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    weekdayCard
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                providersCard
                weekdayCard
            }

            projectsCard
            rhythmCard

            if sessions.count >= 1_000 {
                historyNote
            }
        }
    }

    // MARK: - Pulse

    private var pulseCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usage pulse")
                        .font(.system(size: 12, weight: .semibold))
                    Text(pulseSubtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Picker("Window", selection: rangeBinding) {
                    ForEach(UsageRange.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help("Change the insight window")
            }

            LazyVGrid(columns: metricColumns, spacing: 8) {
                InsightMetricTile(
                    icon: "dollarsign.circle.fill",
                    tint: Theme.accent,
                    label: "Cost",
                    value: Fmt.usd(totals.cost),
                    caption: comparisonCaption,
                    delta: delta(
                        current: totals.cost,
                        previous: previousTotals?.cost,
                        increaseIsPositive: false
                    )
                )
                InsightMetricTile(
                    icon: "cpu",
                    tint: Theme.reasoning,
                    label: "Tokens",
                    value: Fmt.compact(totals.tokens),
                    caption: comparisonCaption,
                    delta: delta(
                        current: totals.tokens,
                        previous: previousTotals?.tokens,
                        increaseIsPositive: true
                    )
                )
                InsightMetricTile(
                    icon: "bolt.fill",
                    tint: Theme.running,
                    label: "Steps",
                    value: Fmt.grouped(totals.steps),
                    caption: comparisonCaption,
                    delta: delta(
                        current: Double(totals.steps),
                        previous: previousTotals.map { Double($0.steps) },
                        increaseIsPositive: true
                    )
                )
                InsightMetricTile(
                    icon: "bubble.left.and.bubble.right.fill",
                    tint: Theme.input,
                    label: "Sessions",
                    value: Fmt.grouped(totals.sessions),
                    caption: sessionsCaption,
                    delta: delta(
                        current: Double(totals.sessions),
                        previous: previousTotals.map { Double($0.sessions) },
                        increaseIsPositive: true
                    )
                )
            }
        }
        .card()
    }

    private var metricColumns: [GridItem] {
        let count = availableWidth >= 620 ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private var pulseSubtitle: String {
        var parts = ["\(totals.activeDays) active day\(totals.activeDays == 1 ? "" : "s")"]
        if totals.subagents > 0 {
            parts.append("\(Fmt.grouped(totals.subagents)) subagents")
        }
        if totals.sessions == 0, totals.steps == 0 {
            parts = ["No activity recorded in this window"]
        }
        return parts.joined(separator: " · ")
    }

    private var comparisonCaption: String {
        previousTotals == nil ? "all recorded usage" : "vs previous \(range.rawValue)"
    }

    private var sessionsCaption: String {
        guard totals.subagents > 0 else { return comparisonCaption }
        return "\(Fmt.grouped(totals.subagents)) subagents · \(comparisonCaption)"
    }

    private func delta(
        current: Double,
        previous: Double?,
        increaseIsPositive: Bool
    ) -> InsightDelta? {
        guard let previous, previous > 0 else { return nil }
        let change = (current - previous) / previous
        guard abs(change) >= 0.005 else {
            return InsightDelta(text: "0%", isUp: false, isFlat: true, increaseIsPositive: increaseIsPositive)
        }
        return InsightDelta(
            text: "\(Int((abs(change) * 100).rounded()))%",
            isUp: change > 0,
            isFlat: false,
            increaseIsPositive: increaseIsPositive
        )
    }

    // MARK: - Providers

    private var providersCard: some View {
        let rows = providers
        let totalCost = rows.reduce(0) { $0 + $1.cost }
        let totalTokens = rows.reduce(0) { $0 + $1.tokens }
        let useCost = totalCost > 0
        let top = Array(rows.prefix(7))

        return VStack(alignment: .leading, spacing: 10) {
            cardHeader(
                "Providers",
                detail: rows.isEmpty ? nil : "\(rows.count) active"
            )

            if rows.isEmpty {
                emptyRow("No provider usage in this window.", icon: "cpu")
            } else {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, provider in
                    let share = useCost
                        ? (totalCost > 0 ? provider.cost / totalCost : 0)
                        : (totalTokens > 0 ? provider.tokens / totalTokens : 0)
                    InsightRankRow(
                        name: provider.name,
                        color: palette[index % palette.count],
                        detail: "\(sessionsLabel(provider.totalSessions)) · \(Fmt.compact(provider.tokens)) tokens",
                        value: useCost ? Fmt.usd(provider.cost) : Fmt.compact(provider.tokens),
                        share: share
                    )
                }

                if rows.count > top.count {
                    Text("+\(rows.count - top.count) more provider\(rows.count - top.count == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .card()
    }

    // MARK: - Projects

    private var projectsCard: some View {
        let rows = projectRows
        let totalCost = rows.reduce(0) { $0 + $1.cost }
        let totalTokens = rows.reduce(0) { $0 + $1.tokens }
        let useCost = totalCost > 0
        let top = Array(rows.prefix(8))

        return VStack(alignment: .leading, spacing: 10) {
            cardHeader(
                "Projects",
                detail: rows.isEmpty ? nil : "\(rows.count) active"
            )

            if rows.isEmpty {
                emptyRow("No project activity in this window.", icon: "folder")
            } else {
                ForEach(top) { project in
                    let share = useCost
                        ? (totalCost > 0 ? project.cost / totalCost : 0)
                        : (totalTokens > 0 ? project.tokens / totalTokens : 0)
                    InsightRankRow(
                        name: project.name,
                        color: Theme.accent,
                        detail: "\(sessionsLabel(project.totalSessions)) · \(Fmt.compact(project.tokens)) tokens",
                        value: useCost ? Fmt.usd(project.cost) : Fmt.compact(project.tokens),
                        share: share
                    )
                }

                if rows.count > top.count {
                    Text("+\(rows.count - top.count) more project\(rows.count - top.count == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .card()
    }

    // MARK: - Weekdays

    private var weekdayCard: some View {
        let rows = weekdays
        let values = rows.map { weekdayMetric.value($0) }
        let total = values.reduce(0, +)
        let peak = rows.max { weekdayMetric.value($0) < weekdayMetric.value($1) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("WEEKDAY RHYTHM")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                HStack(spacing: 3) {
                    ForEach(WeekdayMetric.allCases) { metric in
                        Button {
                            weekdayMetricRaw = metric.rawValue
                        } label: {
                            Text(metric.title)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(weekdayMetric == metric ? metric.color : Color.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(
                                        weekdayMetric == metric
                                            ? metric.color.opacity(0.15)
                                            : Color.clear
                                    )
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Plot \(metric.title.lowercased()) by weekday")
                    }
                }
            }

            if total <= 0 {
                emptyRow("No weekday activity in this window.", icon: "calendar")
                    .frame(height: 122, alignment: .center)
            } else {
                Chart(rows) { row in
                    BarMark(
                        x: .value("Weekday", row.shortName),
                        y: .value(weekdayMetric.title, weekdayMetric.value(row))
                    )
                    .foregroundStyle(
                        (peak?.weekday == row.weekday ? Theme.accent : weekdayMetric.color.opacity(0.65))
                    )
                    .cornerRadius(2)

                    RuleMark(y: .value("Average", total / Double(max(rows.count, 1))))
                        .lineStyle(StrokeStyle(lineWidth: 0.7, dash: [3, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.primary.opacity(0.12))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(weekdayMetric.axisLabel(number))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 122)

                if let peak, weekdayMetric.value(peak) > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.warn)
                        Text("Busiest \(peak.name) · \(weekdayMetric.format(weekdayMetric.value(peak)))")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("avg \(weekdayMetric.format(total / 7))")
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Time of day

    private var rhythmCard: some View {
        let rows = hours
        let peak = rows.max { $0.sessions < $1.sessions }
        let starts = rows.reduce(0) { $0 + $1.sessions }

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("TIME OF DAY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let peak, peak.sessions > 0 {
                    Text("peak \(peak.label)")
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
                Text("·")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("\(starts) session\(starts == 1 ? "" : "s") started")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if starts == 0 {
                emptyRow("No session starts in this window.", icon: "clock")
            } else {
                Chart(rows) { row in
                    BarMark(
                        x: .value("Hour", row.hour),
                        y: .value("Sessions", row.sessions)
                    )
                    .foregroundStyle(
                        row.hour == peak?.hour ? Theme.accent : Theme.running.opacity(0.62)
                    )
                    .cornerRadius(1.5)
                }
                .chartLegend(.hidden)
                .chartXScale(domain: 0...23)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.primary.opacity(0.12))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(Fmt.compact(number))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text(String(format: "%02d", hour))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 96)

                Divider()
                    .opacity(0.45)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("PUNCH CARD")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("weekday × hour")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                PunchCardView(card: punchCard)
            }
        }
        .card()
    }

    // MARK: - Shared pieces

    private func cardHeader(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func emptyRow(_ message: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 40)
    }

    private func sessionsLabel(_ count: Int) -> String {
        "\(Fmt.grouped(count)) session\(count == 1 ? "" : "s")"
    }

    private var palette: [Color] {
        [
            Theme.accent, Theme.running, Theme.reasoning, Theme.warn,
            Theme.input, Theme.cacheWrite, Theme.output,
        ]
    }

    private var historyNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("Provider, project, weekday and hour cards are built from the \(Fmt.grouped(sessions.count)) most recent sessions loaded by the app. Daily steps come from the full stats history.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Metric tile

private struct InsightDelta {
    let text: String
    let isUp: Bool
    let isFlat: Bool
    let increaseIsPositive: Bool

    var tint: Color {
        if isFlat { return .secondary }
        return isUp == increaseIsPositive ? Theme.accent : Theme.warn
    }

    var symbol: String {
        if isFlat { return "minus" }
        return isUp ? "arrow.up.right" : "arrow.down.right"
    }
}

private struct InsightMetricTile: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    var caption: String?
    var delta: InsightDelta?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let delta {
                    HStack(spacing: 2) {
                        Image(systemName: delta.symbol)
                            .font(.system(size: 7, weight: .bold))
                        Text(delta.text)
                            .font(.system(size: 8, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(delta.tint)
                }
            }

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let caption {
                Text(caption)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

// MARK: - Ranked row

private struct InsightRankRow: View {
    let name: String
    let color: Color
    let detail: String
    let value: String
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(value)
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text("\(Int((share * 100).rounded()))%")
                        .font(.system(size: 8))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(color.opacity(0.8))
                        .frame(width: max(geo.size.width * CGFloat(min(max(share, 0), 1)), share > 0 ? 3 : 0))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(value), \(Int((share * 100).rounded())) percent")
    }
}

// MARK: - Weekday metric

private enum WeekdayMetric: String, CaseIterable, Identifiable {
    case steps
    case cost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .cost: return "Cost"
        }
    }

    var color: Color {
        switch self {
        case .steps: return Theme.running
        case .cost: return Theme.accent
        }
    }

    func value(_ row: WeekdayUsage) -> Double {
        switch self {
        case .steps: return Double(row.steps)
        case .cost: return row.cost
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .steps: return Fmt.grouped(Int(value.rounded()))
        case .cost: return Fmt.usd(value)
        }
    }

    func axisLabel(_ value: Double) -> String {
        switch self {
        case .steps: return Fmt.compact(value)
        case .cost: return Fmt.usd(value)
        }
    }
}

// MARK: - Punch card

/// Weekday × hour grid of session starts. Unlike the fixed cell size in the
/// yearly heatmap, this grid stretches to the card width so 24 columns fit in
/// the compact panel as well as the desktop window.
private struct PunchCardView: View {
    let card: UsagePunchCard

    private let leftInset: CGFloat = 27
    private let rightInset: CGFloat = 1
    private let topInset: CGFloat = 1
    private let bottomInset: CGFloat = 14
    private let gap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { _ in
                Canvas { context, size in
                    draw(context, size: size)
                }
            }
            .frame(height: 108)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session starts by weekday and hour")

            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.accent.opacity([0.25, 0.45, 0.7, 1.0][index]))
                    .frame(width: 8, height: 8)
            }
            Text("More")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Text("session starts")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }

    private func draw(_ context: GraphicsContext, size: CGSize) {
        let columns = UsagePunchCard.hours
        let rows = UsagePunchCard.days
        let availableWidth = max(size.width - leftInset - rightInset, 1)
        let availableHeight = max(size.height - topInset - bottomInset, 1)
        let cellWidth = max((availableWidth - CGFloat(columns - 1) * gap) / CGFloat(columns), 1)
        let cellHeight = max((availableHeight - CGFloat(rows - 1) * gap) / CGFloat(rows), 1)

        for row in 0..<rows {
            for column in 0..<columns {
                let x = leftInset + CGFloat(column) * (cellWidth + gap)
                let y = topInset + CGFloat(row) * (cellHeight + gap)
                let rect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
                let path = Path(roundedRect: rect, cornerRadius: 1.6)
                let count = card.count(weekday: row, hour: column)
                context.fill(path, with: .color(color(for: count)))
            }
        }

        for (row, label) in [(0, "Mon"), (2, "Wed"), (4, "Fri"), (6, "Sun")] {
            let y = topInset + CGFloat(row) * (cellHeight + gap) + cellHeight / 2
            let text = Text(label)
                .font(.system(size: 7))
                .foregroundStyle(Color.secondary)
            context.draw(text, at: CGPoint(x: leftInset - 4, y: y), anchor: .trailing)
        }

        for hour in [0, 6, 12, 18] {
            let x = leftInset + CGFloat(hour) * (cellWidth + gap) + cellWidth / 2
            let text = Text(String(format: "%02d", hour))
                .font(.system(size: 7))
                .foregroundStyle(Color.secondary)
            context.draw(text, at: CGPoint(x: x, y: size.height - 1), anchor: .bottom)
        }
    }

    private func color(for count: Int) -> Color {
        guard count > 0, card.maxCount > 0 else {
            return Color.primary.opacity(0.05)
        }
        let ratio = Double(count) / Double(card.maxCount)
        switch ratio {
        case ..<0.25: return Theme.accent.opacity(0.28)
        case ..<0.50: return Theme.accent.opacity(0.48)
        case ..<0.75: return Theme.accent.opacity(0.72)
        default: return Theme.accent
        }
    }
}

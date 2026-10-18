import SwiftUI

/// GitHub-style contribution heatmap of daily agent steps.
struct HeatmapView: View {
    let activity: [Stats.Activity]
    var weeks: Int = 24

    private let cell: CGFloat = 10
    private let gap: CGFloat = 3
    private let leftInset: CGFloat = 16
    private let topInset: CGFloat = 14

    private var canvasWidth: CGFloat { leftInset + CGFloat(weeks) * cell + CGFloat(weeks - 1) * gap }
    private var canvasHeight: CGFloat { topInset + 7 * cell + 6 * gap }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, _ in
                draw(context)
            }
            .frame(width: canvasWidth, height: canvasHeight)
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var legend: some View {
        HStack(spacing: 5) {
            Text("Less").font(.system(size: 8)).foregroundStyle(.secondary)
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.accent.opacity([0.22, 0.45, 0.7, 1.0][index]))
                    .frame(width: 9, height: 9)
            }
            Text("More").font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    private func draw(_ context: GraphicsContext) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 1 // Sunday

        let today = calendar.startOfDay(for: Date())
        let map = Dictionary(activity.map { ($0.date, $0.steps) }, uniquingKeysWith: max)
        let maxSteps = max(map.values.max() ?? 1, 1)

        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        let offsetToWeekStart = weekday - calendar.firstWeekday
        let thisWeekStart = calendar.date(byAdding: .day, value: -offsetToWeekStart, to: today) ?? today
        let gridStart = calendar.date(byAdding: .day, value: -((weeks - 1) * 7), to: thisWeekStart) ?? thisWeekStart

        // Month labels along the top, one per month change.
        var lastMonth = -1
        for week in 0..<weeks {
            guard let columnDate = calendar.date(byAdding: .day, value: week * 7, to: gridStart) else { continue }
            let month = calendar.component(.month, from: columnDate)
            if month != lastMonth {
                lastMonth = month
                let label = Text(Fmt.monthFormatter.string(from: columnDate))
                    .font(.system(size: 8))
                    .foregroundStyle(Color.secondary)
                let x = leftInset + CGFloat(week) * (cell + gap)
                context.draw(label, at: CGPoint(x: x, y: 2), anchor: .topLeading)
            }
        }

        // Weekday labels.
        for (row, label) in [(1, "Mon"), (3, "Wed"), (5, "Fri")] {
            let text = Text(label).font(.system(size: 7)).foregroundStyle(Color.secondary)
            let y = topInset + CGFloat(row) * (cell + gap) + cell / 2
            context.draw(text, at: CGPoint(x: leftInset - 4, y: y), anchor: .trailing)
        }

        // Cells.
        for week in 0..<weeks {
            for day in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: week * 7 + day, to: gridStart) else { continue }
                let x = leftInset + CGFloat(week) * (cell + gap)
                let y = topInset + CGFloat(day) * (cell + gap)
                let rect = CGRect(x: x, y: y, width: cell, height: cell)
                let path = Path(roundedRect: rect, cornerRadius: 2.5)

                if date > today {
                    context.fill(path, with: .color(Color.primary.opacity(0.03)))
                } else {
                    let steps = map[Fmt.dayString(date)] ?? 0
                    context.fill(path, with: .color(color(for: steps, max: maxSteps)))
                }
            }
        }
    }

    private func color(for steps: Int, max maxSteps: Int) -> Color {
        guard steps > 0 else { return Color.primary.opacity(0.06) }
        let ratio = Double(steps) / Double(max(1, maxSteps))
        switch ratio {
        case ..<0.25: return Theme.accent.opacity(0.30)
        case ..<0.50: return Theme.accent.opacity(0.52)
        case ..<0.75: return Theme.accent.opacity(0.74)
        default: return Theme.accent
        }
    }
}

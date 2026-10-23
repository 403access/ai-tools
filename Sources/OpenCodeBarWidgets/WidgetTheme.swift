import SwiftUI
import UIKit

/// Widget-sized version of the panel palette. The app-only `MobileTheme` is
/// built around UIKit traits; these values match it but stay in the widget
/// target.
enum WidgetTheme {
    static let background = dynamic(
        dark: (0.071, 0.075, 0.086),
        light: (0.925, 0.941, 0.953)
    )

    private static func dynamic(
        dark: (CGFloat, CGFloat, CGFloat),
        light: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// The soft wash behind a widget, echoing the app's accent glows.
struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            WidgetTheme.background

            RadialGradient(
                colors: [Theme.accent.opacity(colorScheme == .dark ? 0.18 : 0.14), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 240
            )

            RadialGradient(
                colors: [Theme.input.opacity(colorScheme == .dark ? 0.14 : 0.10), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 220
            )
        }
    }
}

/// Small app mark used in every widget header.
struct WidgetBrand: View {
    var showsWordmark = true

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accent.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.black.opacity(0.75))
            }
            .frame(width: 16, height: 16)

            if showsWordmark {
                Text("OpenCode")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("OpenCode")
    }
}

/// Connection dot with an optional tint for the running state.
struct WidgetStatusDot: View {
    let connection: WidgetSnapshot.Connection
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch connection {
        case .connected: return Theme.accent
        case .connecting: return Theme.warn
        case .offline: return Theme.danger
        case .disabled: return .secondary
        }
    }
}

/// Section heading used inside medium and large widgets.
struct WidgetSectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// One plan-limit row: label, percentage, and a thin progress track.
struct WidgetPlanLimit: View {
    let window: WidgetSnapshot.PlanWindow
    var showsReset = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(window.label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.primary)
                if window.isLimited {
                    Text("limited")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Theme.danger)
                }
                Spacer(minLength: 4)
                if showsReset, let reset = window.resetsAt {
                    Text(Fmt.countdown(to: reset))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                Text("\(Int(window.used))%")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: max(
                                geo.size.width * CGFloat(min(max(window.used, 0), 100) / 100),
                                window.used > 0 ? 3 : 0
                            )
                        )
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.label): \(Int(window.used)) percent used")
    }

    private var tint: Color {
        if window.isLimited { return Theme.danger }
        if window.used >= 80 { return Theme.warn }
        return Theme.accent
    }
}

/// Compact 14-day step chart for the Usage widget.
struct WidgetActivityBars: View {
    let days: [WidgetSnapshot.Day]
    var height: CGFloat = 30

    var body: some View {
        let maxSteps = max(days.map(\.steps).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(days) { day in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(day.steps > 0 ? Theme.accent.opacity(day == days.last ? 1 : 0.55) : Color.primary.opacity(0.10))
                        .frame(height: max(2, height * CGFloat(day.steps) / CGFloat(maxSteps)))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Steps over the last \(days.count) days")
    }
}

/// Empty/unavailable state shared by both widgets.
struct WidgetEmptyState: View {
    let icon: String
    let title: String
    var detail: String?
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

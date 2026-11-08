import ActivityKit
import SwiftUI
import WidgetKit

/// The large Lock Screen card that appears while a session is running.
///
/// This is the ActivityKit counterpart of the Live Sessions widget. It shows
/// the same project-grouped, status-only view with more room than an accessory
/// widget. The appearance follows the style chosen in the app's Settings:
/// the Lock Screen's native material (the default) or the light Mint card.
struct SessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(Theme.accent)
                        Text(state.focusEntry?.title ?? "OpenCode")
                            .lineLimit(1)
                    }
                    .font(.caption2.weight(.semibold))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.summary)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 82)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(state.previewEntries) { entry in
                            HStack(spacing: 4) {
                                Text(entry.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                HStack(spacing: 3) {
                                    Image(systemName: entry.status.icon)
                                    Text(entry.status.shortLabel.uppercased())
                                }
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(islandStatusColor(entry.status))
                                .lineLimit(1)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(Theme.accent)
            } compactTrailing: {
                Text("\(max(state.runningCount, state.reviewCount))")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .frame(maxWidth: 24)
            } minimal: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(Theme.accent)
            }
            .keylineTint(Theme.accent)
        }
    }

    private func islandStatusColor(_ status: WidgetSnapshot.Session.Status) -> Color {
        switch status {
        case .running: return Theme.accent
        case .review: return Theme.warn
        case .queued: return Theme.reasoning
        case .failed, .interrupted: return Theme.danger
        default: return .secondary
        }
    }
}

struct SessionLiveActivityLockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>
    @Environment(\.colorScheme) private var colorScheme

    private var state: SessionActivityAttributes.ContentState { context.state }
    private var palette: LiveActivityPalette {
        LiveActivityPalette.make(state.theme, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if state.groups.isEmpty {
                Text("No sessions need attention")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondaryInk)
            } else {
                ForEach(Array(state.groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Rectangle()
                            .fill(palette.separator)
                            .frame(height: 1)
                            .padding(.vertical, 2)
                    }

                    groupView(group)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            backdrop
        }
        .activityBackgroundTint(palette.backgroundTint)
        .activitySystemActionForegroundColor(palette.ink)
        .widgetURL(WidgetLinks.session(context.attributes.sessionID))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var backdrop: some View {
        switch palette.backdrop {
        case .none:
            EmptyView()
        case .mint:
            RadialGradient(
                colors: [Color.white.opacity(0.7), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 210
            )
            .allowsHitTesting(false)
        case .app:
            ZStack {
                RadialGradient(
                    colors: [Theme.accent.opacity(colorScheme == .dark ? 0.20 : 0.14), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 240
                )
                RadialGradient(
                    colors: [Theme.input.opacity(colorScheme == .dark ? 0.16 : 0.10), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 220
                )
            }
            .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.accent, palette.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 21, height: 21)

            Text("OpenCode")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(palette.ink)

            Text("LIVE")
                .font(.system(size: 8.5, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(palette.livePillText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(palette.livePillFill))

            Spacer(minLength: 6)

            Text(state.summary)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(palette.summaryFill))
        }
    }

    private func groupView(_ group: SessionActivityAttributes.ContentState.Group) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                projectIcon(group.projectID)

                Text(group.project)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.projectInk)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if group.id == state.groups.last?.id, state.hidden > 0 {
                    Text("+\(state.hidden)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(palette.secondaryInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.summaryFill))
                }
            }

            ForEach(group.entries) { entry in
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    statusPill(entry.status)
                }
                .padding(.leading, 26)
            }
        }
    }

    @ViewBuilder
    private func projectIcon(_ projectID: String?) -> some View {
        if let fill = palette.projectTileFill {
            LiveProjectIcon(
                projectID: projectID,
                size: 20,
                fill: fill,
                stroke: palette.projectTileStroke,
                fallback: palette.secondaryInk
            )
        } else {
            WidgetProjectIcon(projectID: projectID, size: 20)
        }
    }

    private func statusPill(_ status: WidgetSnapshot.Session.Status) -> some View {
        HStack(spacing: 3) {
            Image(systemName: status.icon)
                .font(.system(size: 8.5, weight: .heavy))
            Text(status.shortLabel.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(palette.pillForeground(status))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(palette.pillBackground(status)))
    }

    private var accessibilitySummary: String {
        let entries = state.groups.flatMap { group in
            group.entries.map { "\($0.title) in \(group.project), \($0.status.label)" }
        }
        return entries.isEmpty
            ? "No OpenCode sessions need attention."
            : entries.joined(separator: ". ")
    }
}

private enum LiveActivityBackdrop {
    case none
    case mint
    case app
}

/// Colors for the Live Activity styles.
private struct LiveActivityPalette {
    let theme: LiveActivityTheme
    let backgroundTint: Color?
    let ink: Color
    let secondaryInk: Color
    let accent: Color
    let teal: Color
    let separator: Color
    let summaryFill: Color
    let livePillFill: Color
    let livePillText: Color
    let projectInk: Color
    let projectTileFill: Color?
    let projectTileStroke: Color
    let backdrop: LiveActivityBackdrop

    static func make(_ theme: LiveActivityTheme, colorScheme: ColorScheme) -> LiveActivityPalette {
        switch theme {
        case .native:
            return LiveActivityPalette(
                theme: theme,
                backgroundTint: nil,
                ink: .primary,
                secondaryInk: .secondary,
                accent: Theme.accent,
                teal: Theme.running,
                separator: Color.primary.opacity(0.08),
                summaryFill: Color.primary.opacity(0.07),
                livePillFill: Theme.accent,
                livePillText: colorScheme == .dark ? .black : .white,
                projectInk: .primary,
                projectTileFill: nil,
                projectTileStroke: Color.primary.opacity(0.10),
                backdrop: .none
            )
        case .mint:
            return LiveActivityPalette(
                theme: theme,
                backgroundTint: Color(red: 0.88, green: 0.97, blue: 0.92),
                ink: Color(red: 0.04, green: 0.16, blue: 0.12),
                secondaryInk: Color(red: 0.28, green: 0.43, blue: 0.37),
                accent: Color(red: 0.02, green: 0.55, blue: 0.38),
                teal: Color(red: 0.03, green: 0.45, blue: 0.52),
                separator: Color(red: 0.04, green: 0.16, blue: 0.12).opacity(0.07),
                summaryFill: Color.white.opacity(0.55),
                livePillFill: Color(red: 0.02, green: 0.55, blue: 0.38),
                livePillText: .white,
                projectInk: Color(red: 0.04, green: 0.16, blue: 0.12),
                projectTileFill: Color.white.opacity(0.85),
                projectTileStroke: Color.white.opacity(0.8),
                backdrop: .mint
            )
        case .app:
            return LiveActivityPalette(
                theme: theme,
                backgroundTint: WidgetTheme.background,
                ink: .primary,
                secondaryInk: .secondary,
                accent: Theme.accent,
                teal: Theme.accent.opacity(0.55),
                separator: Color.primary.opacity(0.08),
                summaryFill: Color.primary.opacity(0.06),
                livePillFill: Theme.accent,
                livePillText: colorScheme == .dark ? .black : .white,
                projectInk: Theme.accent,
                projectTileFill: nil,
                projectTileStroke: Color.primary.opacity(0.10),
                backdrop: .app
            )
        }
    }

    func pillBackground(_ status: WidgetSnapshot.Session.Status) -> Color {
        switch theme {
        case .native:
            switch status {
            case .running: return Theme.running.opacity(0.18)
            case .review: return Theme.warn.opacity(0.18)
            case .queued: return Theme.reasoning.opacity(0.18)
            case .paused: return Theme.input.opacity(0.15)
            case .stopped: return Color.primary.opacity(0.08)
            case .failed, .interrupted: return Theme.danger.opacity(0.18)
            default: return Color.primary.opacity(0.08)
            }
        case .app:
            switch status {
            case .running: return Theme.running.opacity(0.22)
            case .review: return Theme.warn.opacity(0.22)
            case .queued: return Theme.reasoning.opacity(0.22)
            case .paused: return Theme.input.opacity(0.18)
            case .stopped: return Color.primary.opacity(0.10)
            case .failed, .interrupted: return Theme.danger.opacity(0.22)
            default: return Color.primary.opacity(0.10)
            }
        case .mint:
            switch status {
            case .running: return Color(red: 0.02, green: 0.55, blue: 0.38)
            case .review: return Color(red: 1.00, green: 0.93, blue: 0.77)
            case .queued: return Color(red: 0.92, green: 0.89, blue: 1.00)
            case .paused: return Color(red: 0.88, green: 0.94, blue: 0.99)
            case .stopped: return Color(red: 0.04, green: 0.16, blue: 0.12).opacity(0.08)
            case .failed, .interrupted: return Color(red: 1.00, green: 0.89, blue: 0.89)
            default: return Color(red: 0.04, green: 0.16, blue: 0.12).opacity(0.08)
            }
        }
    }

    func pillForeground(_ status: WidgetSnapshot.Session.Status) -> Color {
        switch theme {
        case .native, .app:
            switch status {
            case .running: return Theme.running
            case .review: return Theme.warn
            case .queued: return Theme.reasoning
            case .paused: return Theme.input
            case .failed, .interrupted: return Theme.danger
            default: return .secondary
            }
        case .mint:
            switch status {
            case .running: return .white
            case .review: return Color(red: 0.48, green: 0.30, blue: 0.02)
            case .queued: return Color(red: 0.35, green: 0.22, blue: 0.75)
            case .paused: return Color(red: 0.20, green: 0.35, blue: 0.55)
            case .failed, .interrupted: return Color(red: 0.68, green: 0.11, blue: 0.12)
            default: return Color(red: 0.28, green: 0.43, blue: 0.37)
            }
        }
    }
}

/// Project artwork on a white tile for the Mint card, with a fallback that
/// stays legible on a light surface.
private struct LiveProjectIcon: View {
    let projectID: String?
    var size: CGFloat = 20
    let fill: Color
    let stroke: Color
    let fallback: Color

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                if let image = WidgetProjectIcons.image(for: projectID) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                        .padding(2)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(fallback)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

private extension SessionActivityAttributes.ContentState {
    var focusEntry: Entry? {
        groups.first?.entries.first
    }

    /// Two rows are the most that comfortably fit under the Dynamic Island.
    var previewEntries: [Entry] {
        Array(groups.flatMap(\.entries).prefix(2))
    }

    var summary: String {
        var parts: [String] = []
        if runningCount > 0 {
            parts.append("\(runningCount) running")
        }
        if reviewCount > 0 {
            parts.append("\(reviewCount) review")
        }
        if queuedCount > 0 {
            parts.append("\(queuedCount) queued")
        }
        return parts.isEmpty ? "Live" : parts.joined(separator: " · ")
    }
}

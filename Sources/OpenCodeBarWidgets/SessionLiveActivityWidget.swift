import ActivityKit
import SwiftUI
import WidgetKit

/// The large Lock Screen card that appears while a session is running.
///
/// This is the ActivityKit counterpart of the Live Sessions widget: the system
/// gives Live Activities a full-width card, so there is room for the project,
/// activity line, todo progress, and live metrics that do not fit in an
/// accessory widget.
struct SessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(Theme.accent)
                        Text(context.state.project)
                            .lineLimit(1)
                    }
                    .font(.caption2.weight(.semibold))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: 58)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let summary = context.state.activitySummary {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let progress = context.state.progress {
                            ProgressView(value: min(max(progress, 0), 1))
                                .tint(Theme.accent)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(Theme.accent)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(Theme.accent)
            }
            .keylineTint(Theme.accent)
        }
    }
}

struct SessionLiveActivityLockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    private var state: SessionActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(state.title)
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(1)

            activityRow

            if let progress = state.progress {
                progressBar(progress)
            }

            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(WidgetLinks.session(context.attributes.sessionID))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.hubConnected ? Theme.accent : Theme.warn)
                .frame(width: 5, height: 5)

            Text(state.hubConnected ? "OPENCODE LIVE" : "OPENCODE · OFFLINE")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            Text(state.countLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var activityRow: some View {
        HStack(spacing: 4) {
            if let icon = state.activityIcon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            Text(state.project)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)

            if let summary = state.activitySummary {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private func progressBar(_ progress: Double) -> some View {
        let fraction = min(max(progress, 0), 1)
        let percent = Int((fraction * 100).rounded())
        return HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(4, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 4)

            Text("\(percent)%")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Task progress")
        .accessibilityValue("\(percent) percent")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(state.startedAt, style: .timer)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            metric(icon: "dollarsign.circle", value: Fmt.usd(state.cost))
            metric(icon: "cpu", value: Fmt.compact(state.tokens))

            Spacer(minLength: 0)
        }
    }

    private func metric(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private var accessibilitySummary: String {
        var parts = ["\(state.title) in \(state.project)"]
        if let summary = state.activitySummary {
            parts.append(summary)
        }
        if let progress = state.progress {
            parts.append("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent of tasks done")
        }
        parts.append("\(state.countLabel.lowercased())")
        return parts.joined(separator: ". ")
    }
}

private extension SessionActivityAttributes.ContentState {
    var countLabel: String {
        runningCount <= 1 ? "1 RUNNING" : "\(runningCount) RUNNING"
    }

    /// "Editing · Sources/LiveWidget.swift", dropping empty halves.
    var activitySummary: String? {
        let parts = [activity, activityDetail]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

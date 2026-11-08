import SwiftUI

/// One section in a `SmartTabBar`.
struct SmartTab<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let icon: String
    /// Optional count or short status shown next to the title, or as a dot on
    /// the icon when the bar is in its compact form.
    var badge: String?
    /// Tooltip text. Defaults to the title.
    var help: String?

    var id: Value { value }
}

/// Segmented tab strip that keeps full labels while they fit and collapses to
/// glyphs when the available width gets tight.
///
/// A segmented control that simply squeezes labels truncates them ("Proj…",
/// "Setti…"), which makes a tab bar harder to scan than a compact icon strip.
/// macOS navigators solve this by showing labels when there is room and glyphs
/// with tooltips when there is not; this view follows that rule. In the compact
/// form the selected tab keeps its title, so the current section is always
/// named. It also carries the small details expected of a Mac control: a hover
/// fill, a selected pill, tooltips, and accessibility labels.
struct SmartTabBar<Value: Hashable>: View {
    let tabs: [SmartTab<Value>]
    @Binding var selection: Value
    var fontSize: CGFloat = 11
    var height: CGFloat = 26
    var accessibilityLabel = "Sections"

    @State private var hovered: Value?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // `ViewThatFits` measures the labelled strip at its ideal width, so
        // labels are never scaled down or truncated: the control switches to
        // its compact form instead.
        ViewThatFits(in: .horizontal) {
            labelStrip
            compactStrip
            glyphStrip
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selection)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Layouts

    private var labelStrip: some View {
        HStack(spacing: 3) {
            ForEach(tabs) { tab in
                segment(tab, showsTitle: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Narrow form: glyphs for every tab, with the selected tab keeping its
    /// title so the current section is always named. The selected segment is
    /// sized to its label and the remaining glyphs share the rest of the bar.
    private var compactStrip: some View {
        HStack(spacing: 3) {
            ForEach(tabs) { tab in
                let isSelected = selection == tab.value
                segment(tab, showsTitle: isSelected)
                    .fixedSize(horizontal: isSelected, vertical: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Last resort for a very narrow split column: glyphs only, with tooltips
    /// and accessibility labels carrying the names.
    private var glyphStrip: some View {
        HStack(spacing: 3) {
            ForEach(tabs) { tab in
                segment(tab, showsTitle: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Segment

    private func segment(_ tab: SmartTab<Value>, showsTitle: Bool) -> some View {
        let isSelected = selection == tab.value
        let isHovered = hovered == tab.value

        return Button {
            guard selection != tab.value else { return }
            selection = tab.value
        } label: {
            HStack(spacing: showsTitle ? 5 : 0) {
                icon(tab, showsBadge: !showsTitle)

                if showsTitle {
                    Text(tab.title)
                        .font(.system(size: fontSize, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let badge = tab.badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.warn)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.warn.opacity(0.16)))
                            .fixedSize()
                    }
                }
            }
            // Label segments share the width evenly; icon segments share the
            // rest of the bar, with a minimum hit target, so the control fills
            // its container instead of leaving ragged gaps.
            .frame(minWidth: showsTitle ? nil : 26, maxWidth: .infinity)
            .frame(height: height)
            .padding(.horizontal, showsTitle ? 4 : 0)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill(isSelected: isSelected, isHovered: isHovered))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tab.help ?? tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            if hovering {
                hovered = tab.value
            } else if hovered == tab.value {
                hovered = nil
            }
        }
    }

    private func icon(_ tab: SmartTab<Value>, showsBadge: Bool) -> some View {
        Image(systemName: tab.icon)
            .font(.system(size: showsBadge ? 12 : 10, weight: .semibold))
            .frame(width: showsBadge ? 16 : 12)
            .overlay(alignment: .topTrailing) {
                if showsBadge, tab.badge != nil {
                    Circle()
                        .fill(Theme.warn)
                        .frame(width: 4, height: 4)
                        .offset(x: 2, y: -1)
                }
            }
    }

    private func fill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return Color.primary.opacity(0.12) }
        if isHovered { return Color.primary.opacity(0.055) }
        return .clear
    }
}

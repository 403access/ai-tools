import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// The palette is shared by both clients. Light mode uses deeper, cooler
// versions of the same hues so labels and icons keep their contrast on white
// cards; the dark values are the original panel colours.
enum Theme {
    static let accent = adaptive(light: (0.043, 0.560, 0.396), dark: (0.30, 0.85, 0.62))
    static let running = adaptive(light: (0.043, 0.490, 0.650), dark: (0.36, 0.80, 0.98))
    static let warn = adaptive(light: (0.647, 0.396, 0.000), dark: (0.98, 0.72, 0.28))
    static let danger = adaptive(light: (0.760, 0.165, 0.200), dark: (0.97, 0.40, 0.42))

    static let input = adaptive(light: (0.173, 0.388, 0.784), dark: (0.42, 0.62, 0.99))
    static let output = adaptive(light: (0.055, 0.530, 0.370), dark: (0.35, 0.84, 0.63))
    static let reasoning = adaptive(light: (0.470, 0.220, 0.700), dark: (0.78, 0.55, 0.98))
    static let cacheRead = adaptive(light: (0.600, 0.380, 0.000), dark: (0.99, 0.72, 0.35))
    static let cacheWrite = adaptive(light: (0.700, 0.165, 0.270), dark: (0.96, 0.47, 0.55))

    private typealias Components = (CGFloat, CGFloat, CGFloat)

    #if canImport(UIKit)
    private static func adaptive(light: Components, dark: Components) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
    #else
    private static func adaptive(light: Components, dark: Components) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
    #endif
}

/// A subtle rounded card container used throughout the panel.
struct Card: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .shadow(color: shadow, radius: colorScheme == .dark ? 0 : 7, y: colorScheme == .dark ? 0 : 2)
    }

    /// Dark cards are a translucent lift over the panel; light cards are solid
    /// white so they read cleanly against the cool grey backdrop.
    private var fill: Color {
        colorScheme == .dark ? Color.primary.opacity(0.05) : .white
    }

    private var border: Color {
        colorScheme == .dark ? Color.primary.opacity(0.07) : Color.black.opacity(0.06)
    }

    private var shadow: Color {
        colorScheme == .dark ? .clear : Color.black.opacity(0.05)
    }
}

extension View {
    func card(padding: CGFloat = 12) -> some View {
        modifier(Card(padding: padding))
    }
}

/// Small pill/badge used for models, agents and statuses.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// Section header with an optional trailing detail view.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

import SwiftUI

enum Theme {
    static let accent = Color(red: 0.30, green: 0.85, blue: 0.62)
    static let running = Color(red: 0.36, green: 0.80, blue: 0.98)
    static let warn = Color(red: 0.98, green: 0.72, blue: 0.28)
    static let danger = Color(red: 0.97, green: 0.40, blue: 0.42)

    static let input = Color(red: 0.42, green: 0.62, blue: 0.99)
    static let output = Color(red: 0.35, green: 0.84, blue: 0.63)
    static let reasoning = Color(red: 0.78, green: 0.55, blue: 0.98)
    static let cacheRead = Color(red: 0.99, green: 0.72, blue: 0.35)
    static let cacheWrite = Color(red: 0.96, green: 0.47, blue: 0.55)
}

/// A subtle rounded card container used throughout the panel.
struct Card: ViewModifier {
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
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

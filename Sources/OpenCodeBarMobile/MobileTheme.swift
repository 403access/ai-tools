import SwiftUI
import UIKit

/// Mobile counterpart of the Mac panel's look: a dark, slightly warm window,
/// translucent cards, and the same accent palette. The colours are dynamic so
/// the app can follow the system appearance when the user asks it to.
enum MobileTheme {
    static let background = dynamic(
        dark: UIColor(red: 0.071, green: 0.075, blue: 0.086, alpha: 1),
        light: UIColor(red: 0.949, green: 0.953, blue: 0.965, alpha: 1)
    )

    static let bar = dynamic(
        dark: UIColor(red: 0.106, green: 0.114, blue: 0.129, alpha: 1),
        light: UIColor(red: 0.984, green: 0.984, blue: 0.992, alpha: 1)
    )

    /// Fill for fields and other recessed controls on top of a card.
    static let field = dynamic(
        dark: UIColor.white.withAlphaComponent(0.055),
        light: UIColor.black.withAlphaComponent(0.045)
    )

    static let border = dynamic(
        dark: UIColor.white.withAlphaComponent(0.09),
        light: UIColor.black.withAlphaComponent(0.07)
    )

    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// The window wash behind every screen. A pair of very soft accent glows keeps
/// the flat dark background from looking like a plain grey sheet.
struct MobileBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MobileTheme.background

            GeometryReader { geo in
                RadialGradient(
                    colors: [Theme.accent.opacity(colorScheme == .dark ? 0.10 : 0.09), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.72
                )

                RadialGradient(
                    colors: [Theme.input.opacity(colorScheme == .dark ? 0.075 : 0.06), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.62
                )
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Applies the shared panel background to a screen.
    func mobileScreenBackground() -> some View {
        background { MobileBackground() }
    }
}

/// User-selected appearance. Dark is the default so a fresh install looks like
/// the Mac menu bar panel.
enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case system
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .system: return "System"
        case .light: return "Light"
        }
    }

    var icon: String {
        switch self {
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .system: return nil
        case .light: return .light
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "opencodebar.appearance"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.storageKey)
        self.appearance = saved.flatMap(AppAppearance.init(rawValue:)) ?? .dark
    }
}

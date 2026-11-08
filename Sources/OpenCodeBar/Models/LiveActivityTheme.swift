import Foundation

/// Visual style for the large session Live Activity card.
///
/// The setting lives in the shared keychain because the app chooses it and the
/// widget extension renders it. The default mirrors the OpenCodeBar panel;
/// System follows the Lock Screen's native material and Mint is the light
/// branded card.
enum LiveActivityTheme: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case native
    case mint
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: return "System"
        case .mint: return "Mint"
        case .app: return "App"
        }
    }

    var detail: String {
        switch self {
        case .native:
            return "Uses the Lock Screen's native material — Liquid Glass on iOS 26 — and follows Light or Dark Mode."
        case .mint:
            return "A light mint card with colorful status pills that stays bright in any appearance."
        case .app:
            return "The default. Matches the OpenCodeBar panel: the app's surface, accent glows, and running/status colors."
        }
    }
}

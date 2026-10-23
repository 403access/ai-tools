import Foundation

/// Hub connection settings for the iOS app and its widgets. Stored in the
/// shared keychain access group so the widget extension can read the same
/// pairing without a second setup step.
struct HubSettings: Codable, Equatable {
    var url: String = ""
    var token: String = ""

    var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var location: HubLocation? {
        guard let parsed = URL(string: trimmedURL),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false,
              !trimmedToken.isEmpty
        else { return nil }
        return HubLocation(url: parsed, token: trimmedToken)
    }

    var isConfigured: Bool { location != nil }

    var displayURL: String {
        guard let parsed = URL(string: trimmedURL), let host = parsed.host else {
            return trimmedURL.isEmpty ? "Not configured" : trimmedURL
        }
        let port = parsed.port.map { ":\($0)" } ?? ""
        return "\(host)\(port)"
    }
}

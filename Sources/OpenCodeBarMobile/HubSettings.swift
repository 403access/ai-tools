import Foundation

/// Hub connection settings for the iOS app. Stored in UserDefaults so the
/// pairing survives launches; the token is a long-lived shared secret generated
/// by the hub.
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

@MainActor
final class HubSettingsStore: ObservableObject {
    @Published var url: String
    @Published var token: String

    private static let storageKey = "opencodebar.hub.settings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(HubSettings.self, from: data) {
            self.url = saved.url
            self.token = saved.token
        } else {
            self.url = ""
            self.token = ""
        }
    }

    var settings: HubSettings {
        HubSettings(url: url, token: token)
    }

    var isConfigured: Bool { settings.isConfigured }

    func save(url: String, token: String) {
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func save(_ settings: HubSettings) {
        save(url: settings.url, token: settings.token)
    }

    func clear() {
        url = ""
        token = ""
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Accepts the link the hub prints at startup:
    /// `opencodebar://pair?url=http%3A%2F%2F192.168.1.5%3A8787&token=…`
    @discardableResult
    func applyPairingLink(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "opencodebar",
              let items = components.queryItems
        else { return false }

        var values: [String: String] = [:]
        for item in items where item.value != nil {
            values[item.name] = item.value
        }
        guard let hubURL = values["url"], let hubToken = values["token"],
              !hubURL.isEmpty, !hubToken.isEmpty
        else { return false }

        save(url: hubURL, token: hubToken)
        return true
    }

    private func persist() {
        let value = HubSettings(url: url, token: token)
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

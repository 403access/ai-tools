import Foundation

/// Resolves the hub connection for the macOS app.
///
/// The hub writes `~/.config/opencode/opencodebar-hub.json` on startup with its
/// URL and token, so the app works without configuration on the same machine.
/// `OPENCODEBAR_HUB_URL` / `OPENCODEBAR_HUB_TOKEN` override it, and
/// `hubURL` / `hubToken` in `opencodebar.json` provide a manual override for a
/// hub running elsewhere.
enum HubDiscovery {
    static let defaultURL = URL(string: "http://127.0.0.1:8787")!

    static func load() -> HubLocation? {
        let environment = ProcessInfo.processInfo.environment
        let hubConfig = readJSON(named: "opencodebar-hub.json")
        let appConfig = readJSON(named: "opencodebar.json")

        let urlString = firstNonEmpty(
            environment["OPENCODEBAR_HUB_URL"],
            appConfig?["hubURL"] as? String,
            hubConfig?["url"] as? String
        )

        let token = firstNonEmpty(
            environment["OPENCODEBAR_HUB_TOKEN"],
            appConfig?["hubToken"] as? String,
            hubConfig?["token"] as? String
        )

        guard let token else { return nil }
        let url = urlString.flatMap(URL.init(string:)) ?? defaultURL
        return HubLocation(url: url, token: token)
    }

    private static func readJSON(named name: String) -> [String: Any]? {
        let url = ServiceDiscovery.configDir().appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}

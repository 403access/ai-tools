import Foundation

@MainActor
final class HubSettingsStore: ObservableObject {
    @Published var url: String
    @Published var token: String

    init() {
        WidgetShared.rememberDeviceID(DeviceIdentity.id)

        #if DEBUG
        // Screenshot and UI-test tooling can pair without the system URL
        // confirmation: `SIMCTL_CHILD_OPENCODEBAR_HUB_URL=…` + `…_TOKEN=…`.
        if let url = ProcessInfo.processInfo.environment["OPENCODEBAR_HUB_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let token = ProcessInfo.processInfo.environment["OPENCODEBAR_HUB_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty, !token.isEmpty {
            self.url = url
            self.token = token
            WidgetShared.saveHubSettings(HubSettings(url: url, token: token))
            return
        }
        #endif

        if let saved = WidgetShared.loadHubSettings() {
            self.url = saved.url
            self.token = saved.token
        } else if let legacy = Self.legacySettings() {
            // Preserve pairings made before the shared keychain existed.
            self.url = legacy.url
            self.token = legacy.token
            WidgetShared.saveHubSettings(legacy)
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
        WidgetShared.clearHubSettings()
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
        WidgetShared.saveHubSettings(value)
    }

    private static func legacySettings() -> HubSettings? {
        guard let data = UserDefaults.standard.data(forKey: WidgetShared.hubSettingsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(HubSettings.self, from: data)
    }
}

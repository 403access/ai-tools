import Foundation
import Security

/// State shared with the Home Screen widgets.
///
/// App extensions do not share `UserDefaults.standard` or the app's SQLite cache.
/// Pairing details and the device id live in a **keychain access group** shared
/// by the app and the extension (the team's provisioning profile already allows
/// it). Each process keeps its own widget snapshot cache; the widget writes a
/// fresh one whenever it talks to the hub, so it still has data offline.
enum WidgetShared {
    /// Preferred suite for snapshots. It is a real shared container only when
    /// the App Group capability is provisioned; otherwise it behaves like a
    /// local suite, which is fine because the widget caches its own fetches.
    static let appGroupID = "group.dev.opencodebar.mobile"

    /// Same key the app has always used.
    static let hubSettingsKey = "opencodebar.hub.settings"
    private static let snapshotKey = "opencodebar.widget.snapshot"
    private static let deviceIDKey = "opencodebar.widget.device.id"

    private static let keychainService = "dev.opencodebar.shared"
    private static let hubAccount = "hub-settings"
    private static let deviceAccount = "device-id"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: - Hub settings

    static func loadHubSettings() -> HubSettings? {
        if let data = keychainData(account: hubAccount),
           let settings = try? JSONDecoder().decode(HubSettings.self, from: data) {
            return settings
        }
        guard let data = defaults.data(forKey: hubSettingsKey) else { return nil }
        return try? JSONDecoder().decode(HubSettings.self, from: data)
    }

    static func saveHubSettings(_ settings: HubSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: hubSettingsKey)
        setKeychainData(data, account: hubAccount)
    }

    static func clearHubSettings() {
        defaults.removeObject(forKey: hubSettingsKey)
        deleteKeychainData(account: hubAccount)
    }

    // MARK: - Device identity

    /// Mirrors `DeviceIdentity.id` into the shared keychain so widget requests
    /// are attributed to the phone app instead of creating a second hub device.
    static func rememberDeviceID(_ id: String) {
        guard !id.isEmpty else { return }
        if defaults.string(forKey: deviceIDKey) != id {
            defaults.set(id, forKey: deviceIDKey)
        }
        if let data = id.data(using: .utf8) {
            setKeychainData(data, account: deviceAccount)
        }
    }

    static var storedDeviceID: String? {
        if let data = keychainData(account: deviceAccount),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }
        let value = defaults.string(forKey: deviceIDKey)
        return value?.isEmpty == false ? value : nil
    }

    // MARK: - Snapshot cache

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func clearSnapshot() {
        defaults.removeObject(forKey: snapshotKey)
    }

    // MARK: - Keychain

    /// Expanded from `$(AppIdentifierPrefix)dev.opencodebar.shared` in the
    /// generated Info.plist, so it stays correct for the signing team.
    private static var sharedAccessGroup: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "OpenCodeBarSharedKeychainGroup"
        ) as? String,
        !value.isEmpty,
        !value.contains("$(")
        else { return nil }
        return value
    }

    private static func keychainQuery(account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func keychainData(account: String) -> Data? {
        if let group = sharedAccessGroup,
           let data = keychainData(account: account, accessGroup: group) {
            return data
        }
        return keychainData(account: account, accessGroup: nil)
    }

    private static func keychainData(account: String, accessGroup: String?) -> Data? {
        var query = keychainQuery(account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    @discardableResult
    private static func setKeychainData(_ data: Data, account: String) -> Bool {
        if let group = sharedAccessGroup,
           setKeychainData(data, account: account, accessGroup: group) {
            return true
        }
        return setKeychainData(data, account: account, accessGroup: nil)
    }

    private static func setKeychainData(
        _ data: Data,
        account: String,
        accessGroup: String?
    ) -> Bool {
        let query = keychainQuery(account: account, accessGroup: accessGroup)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteKeychainData(account: String) {
        if let group = sharedAccessGroup {
            SecItemDelete(keychainQuery(account: account, accessGroup: group) as CFDictionary)
        }
        SecItemDelete(keychainQuery(account: account, accessGroup: nil) as CFDictionary)
    }
}

import Foundation

#if canImport(UIKit)
import Security
import UIKit
#elseif canImport(AppKit)
import AppKit
import IOKit
#endif

/// Stable identity for this device, sent with every hub request so the settings
/// screen can list the Mac and iOS apps connected to the hub.
///
/// The id must not change when the app is updated, reinstalled, or rebuilt:
/// otherwise the hub keeps the old row and lists the same device twice. On iOS
/// the id is kept in the keychain (which survives reinstalls); on macOS it is
/// derived from the hardware UUID so debug builds and the bundled app agree.
enum DeviceIdentity {
    static let id: String = {
        #if canImport(AppKit)
        if let hardware = hardwareIdentifier() {
            return hardware
        }
        #endif

        if let stored = keychainIdentifier() {
            return stored
        }
        if let saved = storedIdentifier() {
            // Migrate ids created before the keychain fallback existed.
            saveKeychainIdentifier(saved)
            return saved
        }

        let generated = identifier(from: UUID().uuidString)
        saveIdentifier(generated)
        saveKeychainIdentifier(generated)
        return generated
    }()

    /// Resolved once: the Mac host name can require a reverse lookup.
    static let name: String = {
        #if canImport(UIKit)
        let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return deviceName.isEmpty ? "iPhone" : deviceName
        #elseif canImport(AppKit)
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return hostName.isEmpty ? "Mac" : hostName
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }()

    static let platform: String = {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #elseif canImport(AppKit)
        return "macOS"
        #else
        return "unknown"
        #endif
    }()

    static let appVersion: String = {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let parts = [short, build].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? "dev" : parts.joined(separator: ".")
    }()

    static let headers: [String: String] = [
        "X-OpenCodeBar-Device-Id": id,
        "X-OpenCodeBar-Device-Name": name,
        "X-OpenCodeBar-Platform": platform,
        "X-OpenCodeBar-App-Version": appVersion,
    ]

    // MARK: - Persistent id

    private static let defaultsKey = "opencodebar.device.id"
    private static let keychainService = "dev.opencodebar.device"
    private static let keychainAccount = "device-id"
    /// Marks ids that already use the stable scheme. The hub only merges rows
    /// without this prefix, which are left over from the random per-install ids.
    private static let stablePrefix = "dev-"

    private static func identifier(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix(stablePrefix) ? trimmed : stablePrefix + trimmed
    }

    private static func storedIdentifier() -> String? {
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        guard let saved, !saved.isEmpty else { return nil }
        return identifier(from: saved)
    }

    private static func saveIdentifier(_ value: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }

    #if canImport(AppKit)
    /// A stable id for this Mac, shared by every build of the app.
    private static func hardwareIdentifier() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }
        let value = property.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : identifier(from: value)
    }
    #endif

    #if canImport(UIKit)
    /// Keychain items outlive app updates and reinstalls, unlike user defaults.
    private static func keychainIdentifier() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return identifier(from: value)
    }

    private static func saveKeychainIdentifier(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var insert = query
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }
    #else
    private static func keychainIdentifier() -> String? { nil }

    private static func saveKeychainIdentifier(_ value: String) {}
    #endif
}

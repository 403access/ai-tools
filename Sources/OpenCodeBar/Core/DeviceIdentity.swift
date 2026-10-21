import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Stable identity for this app installation, sent with every hub request so the
/// settings screen can list the Mac and iOS apps connected to the hub.
enum DeviceIdentity {
    static let id: String = {
        let key = "opencodebar.device.id"
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: key)
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
}

import Foundation
import SwiftUI
import UIKit

/// Project artwork for the Lock Screen widget.
///
/// The extension fetches the same `/api/project/:id/icon` payload the app uses
/// and keeps a small on-disk cache in the extension's own container, because
/// the app and extension do not share an App Group. Icons change rarely, so
/// they are revalidated once a day and misses retry hourly.
enum WidgetProjectIcons {
    private static let lock = NSLock()
    private static var memory: [String: UIImage] = [:]
    private static var missing: Set<String> = []

    private static let attemptsKey = "opencodebar.widget.project.icon.attempts"
    private static let iconTTL: TimeInterval = 24 * 60 * 60
    private static let retryTTL: TimeInterval = 60 * 60
    private static let maxFetchesPerRefresh = 6

    /// Fetches artwork for the projects represented in the snapshot before the
    /// timeline entry is rendered. Failures leave the folder fallback in place
    /// and wait an hour before trying again.
    static func prefetch(for snapshot: WidgetSnapshot, settings: HubSettings) async {
        guard let location = settings.location else { return }
        let ids = Set(
            (snapshot.running + snapshot.recent).compactMap(\.projectID)
        )
        guard !ids.isEmpty else { return }

        let wanted = ids.filter(shouldFetch).prefix(maxFetchesPerRefresh)
        guard !wanted.isEmpty else { return }

        let api = HubAPI(location: location)
        await withTaskGroup(of: (String, Data?).self) { group in
            for id in wanted {
                group.addTask { (id, await api.projectIcon(id: id)) }
            }
            for await (id, data) in group {
                markAttempt(id)
                if let data, let image = UIImage(data: data) {
                    store(image: image, data: data, for: id)
                } else {
                    lock.lock()
                    missing.insert(id)
                    lock.unlock()
                }
            }
        }
    }

    /// Synchronous read used by the widget views. The first miss falls back to
    /// the folder glyph, then `prefetch` fills the cache for the next entry.
    static func image(for projectID: String?) -> UIImage? {
        guard let projectID else { return nil }

        lock.lock()
        if let cached = memory[projectID] {
            lock.unlock()
            return cached
        }
        if missing.contains(projectID) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: fileURL(for: projectID)),
              let image = UIImage(data: data)
        else {
            lock.lock()
            missing.insert(projectID)
            lock.unlock()
            return nil
        }

        lock.lock()
        memory[projectID] = image
        lock.unlock()
        return image
    }

    // MARK: - Cache

    private static func store(image: UIImage, data: Data, for id: String) {
        lock.lock()
        memory[id] = image
        missing.remove(id)
        lock.unlock()
        try? data.write(to: fileURL(for: id), options: .atomic)
    }

    private static func shouldFetch(_ id: String) -> Bool {
        if let attempted = attemptDate(id),
           Date().timeIntervalSince(attempted) < retryTTL {
            return false
        }
        if let attributes = try? FileManager.default.attributesOfItem(
            atPath: fileURL(for: id).path
        ),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < iconTTL {
            return false
        }
        return true
    }

    private static func fileURL(for id: String) -> URL {
        let name = Data(id.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directoryURL.appendingPathComponent(name)
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("ProjectIcons", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func attemptDate(_ id: String) -> Date? {
        attempts()[id].map { Date(timeIntervalSince1970: $0) }
    }

    private static func attempts() -> [String: Double] {
        guard let data = WidgetShared.defaults.data(forKey: attemptsKey),
              let map = try? JSONDecoder().decode([String: Double].self, from: data)
        else {
            return [:]
        }
        return map
    }

    private static func markAttempt(_ id: String) {
        var map = attempts()
        map[id] = Date().timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(map) else { return }
        WidgetShared.defaults.set(data, forKey: attemptsKey)
    }
}

/// Rounded project artwork used by the Lock Screen list.
struct WidgetProjectIcon: View {
    let projectID: String?
    var size: CGFloat = 13

    var body: some View {
        Group {
            if let image = WidgetProjectIcons.image(for: projectID) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .overlay(
                        Image(systemName: "folder.fill")
                            .font(.system(size: size * 0.58, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }
}

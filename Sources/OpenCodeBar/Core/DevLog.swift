import Combine
import Foundation

/// In-memory activity log for the Developer view in Settings.
///
/// The log records hub requests, sync cycles, event-stream transitions, and
/// errors so the apps can explain what they are doing without a debugger or
/// stderr access. It is deliberately small and local: entries never include
/// the hub token, request bodies, or response payloads.
///
/// Recording happens from background network tasks, so the buffer is guarded
/// by a lock and published to SwiftUI on the main thread. `entries` is newest
/// first; the copy/export text is chronological.
final class DevLog: ObservableObject {
    static let shared = DevLog()

    enum Category: String, CaseIterable, Identifiable {
        case api = "API"
        case sync = "Sync"
        case events = "Events"
        case app = "App"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .api: return "arrow.up.arrow.down"
            case .sync: return "arrow.triangle.2.circlepath"
            case .events: return "dot.radiowaves.left.and.right"
            case .app: return "app"
            }
        }
    }

    enum Level: Int, Comparable {
        case info
        case warning
        case error

        var isIssue: Bool { self != .info }

        var label: String {
            switch self {
            case .info: return "info"
            case .warning: return "warning"
            case .error: return "error"
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Entry: Identifiable, Equatable {
        let id: UInt64
        let date: Date
        let category: Category
        let level: Level
        let title: String
        let detail: String?
    }

    /// Shared filter menu used by the Mac and iOS developer views.
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case api = "API"
        case sync = "Sync"
        case events = "Events"
        case issues = "Issues"

        var id: String { rawValue }

        func matches(_ entry: Entry) -> Bool {
            switch self {
            case .all: return true
            case .api: return entry.category == .api
            case .sync: return entry.category == .sync
            case .events: return entry.category == .events
            case .issues: return entry.level.isIssue
            }
        }
    }

    /// Newest first, capped at the instance capacity.
    @Published private(set) var entries: [Entry] = []

    private let capacity: Int
    private let lock = NSLock()
    private var buffer: [Entry] = []
    private var nextID: UInt64 = 0
    private var pendingFlush = false

    init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
    }

    // MARK: - Recording

    func record(
        _ title: String,
        category: Category,
        level: Level = .info,
        detail: String? = nil
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        nextID += 1
        buffer.append(Entry(
            id: nextID,
            date: Date(),
            category: category,
            level: level,
            title: trimmedTitle,
            detail: (trimmedDetail?.isEmpty ?? true) ? nil : trimmedDetail
        ))
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        let needsFlush = !pendingFlush
        if needsFlush { pendingFlush = true }
        lock.unlock()

        if needsFlush { scheduleFlush() }
    }

    /// Records one hub request. Query strings stay intact so a failure can be
    /// traced to the exact endpoint; request bodies and headers never appear.
    func api(
        method: String,
        path: String,
        status: Int? = nil,
        duration: TimeInterval,
        bytes: Int? = nil,
        error: String? = nil
    ) {
        var parts: [String] = []
        if let status { parts.append("\(status)") }
        parts.append(Self.durationText(duration))
        if let bytes, bytes > 0 { parts.append(Self.byteText(bytes)) }
        if let error, !error.isEmpty { parts.append(error) }

        let level: Level
        if let error, !error.isEmpty {
            level = (status == nil || (status ?? 0) >= 500) ? .error : .warning
        } else {
            level = .info
        }

        record(
            "\(method) \(path)",
            category: .api,
            level: level,
            detail: parts.joined(separator: " · ")
        )
    }

    func sync(_ title: String, detail: String? = nil, level: Level = .info) {
        record(title, category: .sync, level: level, detail: detail)
    }

    // MARK: - Display and export

    var issueCount: Int {
        entries.reduce(into: 0) { count, entry in
            if entry.level.isIssue { count += 1 }
        }
    }

    /// Chronological text for copying into a bug report.
    var text: String {
        Self.text(for: entries)
    }

    static func text(for entries: [DevLog.Entry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        return entries.reversed().map { entry in
            var line = "\(formatter.string(from: entry.date)) [\(entry.category.rawValue)]"
            if entry.level != .info {
                line += " [\(entry.level.label)]"
            }
            line += " \(entry.title)"
            if let detail = entry.detail {
                line += " — \(detail)"
            }
            return line
        }
        .joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        let needsFlush = !pendingFlush
        if needsFlush { pendingFlush = true }
        lock.unlock()

        if needsFlush { scheduleFlush() }
    }

    // MARK: - Flushing

    private func scheduleFlush() {
        if Thread.isMainThread {
            flush()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.flush()
            }
        }
    }

    private func flush() {
        lock.lock()
        let snapshot = Array(buffer.reversed())
        pendingFlush = false
        lock.unlock()

        entries = snapshot
    }

    // MARK: - Formatting

    static func durationText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 ms" }
        if seconds < 1 {
            return "\(Int((seconds * 1_000).rounded())) ms"
        }
        return String(format: "%.2f s", seconds)
    }

    static func byteText(_ bytes: Int) -> String {
        if bytes < 1_024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return "\(bytes / 1_024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

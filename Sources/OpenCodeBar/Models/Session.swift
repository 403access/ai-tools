import Foundation

// MARK: - Session

struct Session: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var parentID: String?
    var projectID: String
    var agent: String?
    var model: ModelRef?
    var cost: Double
    var tokens: TokenUsage
    var outcome: String?
    var time: Time
    var title: String?
    var subpath: String?
    /// Present when OpenCode created this session as a fork of another one.
    var fork: Fork? = nil
    /// Present when this top-level session is managed on the task board.
    var task: SessionTask? = nil
    var location: Location

    /// The source conversation a fork was copied from.
    struct Fork: Codable, Hashable, Sendable {
        var sessionID: String
        var boundary: Boundary?

        /// Where the fork was cut in the source conversation.
        struct Boundary: Codable, Hashable, Sendable {
            var type: String?
            var messageID: String?
        }
    }

    struct Time: Codable, Hashable, Sendable {
        var created: Double
        var updated: Double
        var idle: Double?
        var viewed: Double?
        var archived: Double?

        var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
        var updatedDate: Date { Date(timeIntervalSince1970: updated / 1000) }
    }

    struct Location: Codable, Hashable, Sendable {
        var directory: String?
    }

    var isSubagent: Bool { parentID != nil }
    var isFork: Bool { fork != nil }
    var directory: String? { location.directory }
    var displayTitle: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled session" : t
    }

    /// Human-readable terminal state for a session that is no longer running.
    var outcomeLabel: String {
        switch outcome {
        case "failed": return "Failed"
        case "interrupted": return "Interrupted"
        default: return "Finished"
        }
    }

    var hasFailureOutcome: Bool {
        outcome == "failed" || outcome == "interrupted"
    }
}

// MARK: - Task board

/// One automatically derived hint such as Bug, Technical, or Breaking change.
struct TaskLabel: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    /// `type`, `scope`, or `risk`. Clients colour and group chips by this.
    var kind: String
}

/// Task-board state attached to a top-level session by the hub. The status is
/// derived: running sessions are working, finished ones wait for review, and a
/// new prompt reopens a resolved task.
struct SessionTask: Codable, Hashable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case working
        case review
        case done
        case dismissed

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .review
        }
    }

    var status: Status
    var labels: [TaskLabel] = []
    /// Milliseconds since the epoch when the hub began tracking this task.
    var createdAt: Double?
    /// Set when the user marked the task done or dismissed.
    var doneAt: Double?

    var doneDate: Date? {
        doneAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

/// Which slice of the task board a view is showing.
enum TaskBoardFilter: String, CaseIterable, Identifiable, Sendable {
    case review
    case working
    case done
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: return "Needs review"
        case .working: return "In progress"
        case .done: return "Done"
        case .all: return "All tasks"
        }
    }

    var shortTitle: String {
        switch self {
        case .review: return "Review"
        case .working: return "Working"
        case .done: return "Done"
        case .all: return "All"
        }
    }

    var icon: String {
        switch self {
        case .review: return "sparkle.magnifyingglass"
        case .working: return "bolt.fill"
        case .done: return "checkmark.circle.fill"
        case .all: return "square.stack.3d.up"
        }
    }

    func matches(_ status: SessionTask.Status) -> Bool {
        switch self {
        case .review: return status == .review
        case .working: return status == .working
        case .done: return status == .done
        case .all: return true
        }
    }
}

extension Session {
    var taskStatus: SessionTask.Status? { task?.status }

    var isFinishedTask: Bool {
        guard let status = task?.status else { return false }
        return status == .review || status == .done
    }
}

extension TaskLabel {
    /// SF Symbol used by both clients for this automatic label.
    var systemImage: String {
        switch id {
        case "bug": return "ladybug.fill"
        case "feature": return "sparkles"
        case "refactor": return "arrow.triangle.2.circlepath"
        case "tests": return "testtube.2"
        case "docs": return "doc.text"
        case "performance": return "speedometer"
        case "security": return "lock.shield.fill"
        case "chore": return "wrench.and.screwdriver.fill"
        case "question": return "questionmark.circle"
        case "product": return "person.crop.rectangle"
        case "technical": return "chevron.left.forwardslash.chevron.right"
        case "infrastructure": return "server.rack"
        case "security-sensitive": return "exclamationmark.shield.fill"
        case "data-loss": return "externaldrive.badge.exclamationmark"
        case "breaking-change": return "exclamationmark.triangle.fill"
        default: return "tag"
        }
    }
}

extension SessionTask.Status {
    var title: String {
        switch self {
        case .working: return "In progress"
        case .review: return "Needs review"
        case .done: return "Done"
        case .dismissed: return "Dismissed"
        }
    }

    var icon: String {
        switch self {
        case .working: return "bolt.fill"
        case .review: return "sparkle.magnifyingglass"
        case .done: return "checkmark.circle.fill"
        case .dismissed: return "eye.slash.fill"
        }
    }
}

// MARK: - Project

struct Project: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var canonical: String
    var vcs: String?
    var name: String?
    var time: Time
    var sandboxes: [String]

    struct Time: Codable, Hashable, Sendable {
        var created: Double
        var updated: Double
        var active: Double?

        var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
        var updatedDate: Date { Date(timeIntervalSince1970: updated / 1000) }
        var activeDate: Date? { active.map { Date(timeIntervalSince1970: $0 / 1000) } }
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        let leaf = URL(fileURLWithPath: canonical).lastPathComponent
        if !leaf.isEmpty { return leaf }
        return canonical.isEmpty ? "Unknown project" : canonical
    }

    /// Most recent activity we know about for this project.
    var lastActiveDate: Date { time.activeDate ?? time.updatedDate }
}

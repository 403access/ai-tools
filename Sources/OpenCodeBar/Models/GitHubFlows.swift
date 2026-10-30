import Foundation

// MARK: - GitHub Actions flows

/// Normalized state shared by workflow runs, jobs, steps and checks.
enum GitHubFlowStatus: String, Decodable, Hashable, Sendable {
    case queued
    case running
    case success
    case failure
    case cancelled
    case skipped
    case neutral
    case waiting
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GitHubFlowStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .success: return "Passed"
        case .failure: return "Failed"
        case .cancelled: return "Cancelled"
        case .skipped: return "Skipped"
        case .neutral: return "Neutral"
        case .waiting: return "Waiting"
        case .unknown: return "Unknown"
        }
    }

    var isRunning: Bool { self == .running }
    var isPending: Bool { self == .queued || self == .waiting }
    var isFailure: Bool { self == .failure }
}

struct GitHubFlowRepository: Decodable, Hashable, Sendable {
    var owner: String
    var name: String
    var url: String
    var remote: String

    var fullName: String { "\(owner)/\(name)" }
}

struct GitHubFlowActor: Decodable, Hashable, Sendable {
    var login: String
    var avatarURL: String?
}

struct GitHubFlowRun: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var runNumber: Int
    var attempt: Int
    var workflowID: Int
    var workflowName: String
    var workflowPath: String?
    var event: String
    var status: GitHubFlowStatus
    var conclusion: String?
    var branch: String
    var sha: String
    var shortSHA: String
    var title: String
    var message: String?
    var actor: GitHubFlowActor?
    var createdAt: Double
    var startedAt: Double?
    var updatedAt: Double?
    var durationMs: Double
    var htmlURL: String

    var createdDate: Date { Date(timeIntervalSince1970: createdAt / 1000) }
}

struct GitHubFlowStep: Decodable, Identifiable, Hashable, Sendable {
    var number: Int
    var name: String
    var status: GitHubFlowStatus
    var conclusion: String?
    var startedAt: Double?
    var completedAt: Double?
    var durationMs: Double

    var id: Int { number }
}

struct GitHubFlowJob: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var status: GitHubFlowStatus
    var conclusion: String?
    var startedAt: Double?
    var completedAt: Double?
    var durationMs: Double
    var runnerName: String?
    var labels: [String]
    var htmlURL: String
    var stage: Int
    var steps: [GitHubFlowStep]
}

struct GitHubFlowStage: Decodable, Identifiable, Hashable, Sendable {
    var index: Int
    var name: String
    var status: GitHubFlowStatus
    var jobs: [GitHubFlowJob]

    var id: Int { index }
}

struct GitHubFlowCommit: Decodable, Hashable, Sendable {
    var sha: String
    var shortSHA: String
    var message: String
    var authorName: String
    var authorLogin: String?
    var additions: Int
    var deletions: Int
    var changedFiles: Int
    var url: String
}

struct GitHubCheckAnnotation: Decodable, Identifiable, Hashable, Sendable {
    var path: String
    var startLine: Int
    var endLine: Int
    var level: String
    var title: String?
    var message: String

    var id: String { "\(path):\(startLine):\(title ?? ""):\(message)" }

    var isFailure: Bool { level == "failure" }
    var isWarning: Bool { level == "warning" }
}

struct GitHubCheck: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var status: GitHubFlowStatus
    var conclusion: String?
    var startedAt: Double?
    var completedAt: Double?
    var durationMs: Double
    var detailsURL: String?
    var description: String?
    var summary: String?
    var appName: String?
    var annotations: [GitHubCheckAnnotation]
}

/// The selected run plus its jobs, stages and checks. The run fields are
/// decoded through `GitHubFlowRun` so both endpoints share one shape.
struct GitHubFlowRunDetail: Decodable, Hashable, Sendable {
    var run: GitHubFlowRun
    var jobs: [GitHubFlowJob]
    var stages: [GitHubFlowStage]
    var checks: [GitHubCheck]

    private enum CodingKeys: String, CodingKey {
        case jobs, stages, checks
    }

    init(from decoder: Decoder) throws {
        run = try GitHubFlowRun(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobs = try container.decodeIfPresent([GitHubFlowJob].self, forKey: .jobs) ?? []
        stages = try container.decodeIfPresent([GitHubFlowStage].self, forKey: .stages) ?? []
        checks = try container.decodeIfPresent([GitHubCheck].self, forKey: .checks) ?? []
    }
}

struct GitHubFlows: Decodable, Hashable, Sendable {
    var repository: GitHubFlowRepository
    var branch: String?
    var runs: [GitHubFlowRun]
    var run: GitHubFlowRunDetail?
    var commit: GitHubFlowCommit?
    var generatedAt: Double

    var generatedDate: Date { Date(timeIntervalSince1970: generatedAt / 1000) }
}

struct GitHubFlowsResponse: Decodable {
    var data: GitHubFlows?
}

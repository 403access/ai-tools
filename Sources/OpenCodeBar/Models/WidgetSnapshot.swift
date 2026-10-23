import Foundation

/// Compact, widget-friendly view of the hub state.
///
/// The app writes one of these whenever its live/usage data changes. Widgets
/// also build one directly from the hub when they refresh, so they keep working
/// while the app is closed. The shape is intentionally smaller than the full
/// SQLite cache: only the rows and totals a Home Screen widget can display.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Session: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var project: String
        var model: String?
        var agent: String?
        var startedAt: Date
        var updatedAt: Date
        var cost: Double
        var tokens: Double
        var activity: String?
        var activityDetail: String?
        var activityIcon: String?
        var subagents: Int
    }

    struct Day: Codable, Equatable, Sendable, Identifiable {
        /// Local calendar day, formatted `yyyy-MM-dd` like the stats payload.
        var date: String
        var steps: Int

        var id: String { date }
    }

    struct Metrics: Codable, Equatable, Sendable {
        var todaySteps: Int
        var totalSteps: Int
        var sessions: Int
        var prompts: Int
        var streak: Int
        var activeDays: Int
        var cost: Double
        var generatedTokens: Double
        var cacheReadTokens: Double
        var toolCalls: Int
        var subagents: Int
        /// Oldest first, used by the compact activity chart.
        var days: [Day]
    }

    struct PlanWindow: Codable, Equatable, Sendable, Identifiable {
        var label: String
        var used: Double
        var resetsAt: Date?
        var isLimited: Bool

        var id: String { label }
    }

    struct Usage: Codable, Equatable, Sendable {
        var configured: Bool
        var windows: [PlanWindow]
        /// Present when the hub is showing stale limits or the fetch failed.
        var note: String?
    }

    enum Connection: String, Codable, Equatable, Sendable {
        case connected
        case connecting
        case offline
        case disabled

        var label: String {
            switch self {
            case .connected: return "Connected"
            case .connecting: return "Connecting"
            case .offline: return "Offline"
            case .disabled: return "Not configured"
            }
        }
    }

    var generatedAt: Date
    var connection: Connection
    /// Short explanation for an offline/disabled state.
    var message: String?
    var hubVersion: String?
    var activeCount: Int
    var running: [Session]
    var recent: [Session]
    var metrics: Metrics?
    var usage: Usage?

    var isEmpty: Bool {
        running.isEmpty && recent.isEmpty && metrics == nil && connection != .connected
    }
}

// MARK: - Samples

extension WidgetSnapshot {
    static func empty(
        connection: Connection = .connecting,
        message: String? = nil
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(),
            connection: connection,
            message: message,
            hubVersion: nil,
            activeCount: 0,
            running: [],
            recent: [],
            metrics: nil,
            usage: nil
        )
    }

    static func placeholder(connection: Connection = .connected) -> WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(
            generatedAt: now.addingTimeInterval(-45),
            connection: connection,
            message: nil,
            hubVersion: "1.0",
            activeCount: 2,
            running: [
                Session(
                    id: "sample-1",
                    title: "Add Home Screen widgets",
                    project: "ai-tools",
                    model: "claude-sonnet-4-5",
                    agent: "build",
                    startedAt: now.addingTimeInterval(-754),
                    updatedAt: now.addingTimeInterval(-8),
                    cost: 1.42,
                    tokens: 184_300,
                    activity: "Editing",
                    activityDetail: "Sources/OpenCodeBarWidgets/LiveWidget.swift",
                    activityIcon: "wrench.and.screwdriver.fill",
                    subagents: 1
                ),
                Session(
                    id: "sample-2",
                    title: "Tune usage trend chart",
                    project: "website",
                    model: "gpt-5",
                    agent: nil,
                    startedAt: now.addingTimeInterval(-2_510),
                    updatedAt: now.addingTimeInterval(-22),
                    cost: 0.36,
                    tokens: 51_200,
                    activity: "Thinking",
                    activityDetail: nil,
                    activityIcon: "brain",
                    subagents: 0
                ),
            ],
            recent: [
                Session(
                    id: "sample-3",
                    title: "Cache hub health responses",
                    project: "ai-tools",
                    model: "claude-sonnet-4-5",
                    agent: nil,
                    startedAt: now.addingTimeInterval(-8_400),
                    updatedAt: now.addingTimeInterval(-3_600),
                    cost: 0.82,
                    tokens: 92_100,
                    activity: nil,
                    activityDetail: nil,
                    activityIcon: nil,
                    subagents: 0
                ),
            ],
            metrics: Metrics(
                todaySteps: 128,
                totalSteps: 3_482,
                sessions: 214,
                prompts: 1_106,
                streak: 12,
                activeDays: 48,
                cost: 128.44,
                generatedTokens: 24_600_000,
                cacheReadTokens: 91_200_000,
                toolCalls: 5_281,
                subagents: 63,
                days: sampleDays()
            ),
            usage: Usage(
                configured: true,
                windows: [
                    PlanWindow(label: "Rolling", used: 34, resetsAt: now.addingTimeInterval(3_200), isLimited: false),
                    PlanWindow(label: "Weekly", used: 61, resetsAt: now.addingTimeInterval(345_600), isLimited: false),
                    PlanWindow(label: "Monthly", used: 82, resetsAt: now.addingTimeInterval(1_900_000), isLimited: false),
                ],
                note: nil
            )
        )
    }

    private static func sampleDays() -> [Day] {
        let values = [42, 88, 51, 120, 74, 0, 63, 96, 143, 87, 38, 110, 71, 128]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return values.enumerated().map { offset, steps in
            let date = calendar.date(byAdding: .day, value: offset - (values.count - 1), to: today) ?? today
            return Day(date: Fmt.dayString(date), steps: steps)
        }
    }
}

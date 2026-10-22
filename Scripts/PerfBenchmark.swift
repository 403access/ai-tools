import Foundation

func nowMS() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }
func measure(_ iterations: Int, _ block: () -> Void) -> Double {
    let start = nowMS()
    for _ in 0..<iterations { block() }
    return (nowMS() - start) / Double(iterations)
}

func syntheticSessions(_ count: Int, days: Int) -> [Session] {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    return (0..<count).map { index in
        let day = index % days
        let updated = base.addingTimeInterval(Double(day * 86_400 + index))
        return Session(
            id: "ses_\(index)",
            parentID: index % 17 == 0 ? "ses_\(max(0, index - 1))" : nil,
            projectID: "prj_\(index % 80)",
            agent: "build",
            model: ModelRef(id: "model-\(index % 6)", providerID: "provider", variant: nil),
            cost: Double(index % 100) / 37,
            tokens: TokenUsage(input: 1000, output: 500, reasoning: 100, cache: .init(read: 8000, write: 200)),
            outcome: "succeeded",
            time: .init(created: updated.addingTimeInterval(-600).timeIntervalSince1970 * 1000,
                        updated: updated.timeIntervalSince1970 * 1000,
                        idle: nil, viewed: nil, archived: nil),
            title: "Session \(index)",
            subpath: nil,
            location: .init(directory: "/tmp/project-\(index % 80)")
        )
    }
}

func syntheticStats(days: Int) -> Stats {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let activity = (0..<days).map { offset -> Stats.Activity in
        let date = base.addingTimeInterval(Double(offset * 86_400))
        return Stats.Activity(date: Fmt.dayString(date), steps: (offset * 13) % 400)
    }
    return Stats(
        range: .init(from: base.timeIntervalSince1970 * 1000,
                     to: base.addingTimeInterval(Double(days * 86_400)).timeIntervalSince1970 * 1000),
        sessions: 1000, subagents: 40, prompts: 2000, steps: 80_000,
        tokens: .init(input: 1_000_000, output: 400_000, reasoning: 90_000,
                      cache: .init(read: 8_000_000, write: 300_000)),
        cost: 42.5, tools: .init(mode: "detail", totals: .init(calls: 9_000, succeeded: 8_600, failed: 200, unfinished: 200), usage: []),
        activeDays: days, streak: 12, activity: activity, models: []
    )
}

func syntheticProjects(_ count: Int) -> [Project] {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    // Every 10th canonical path appears twice, matching the duplicate records
    // OpenCode can leave behind.
    return (0..<count + count / 10).map { index in
        let source = index >= count ? index - count : index
        let canonical = "/Users/dev/project-\(source % count)"
        return Project(
            id: "prj_\(index)",
            canonical: canonical,
            vcs: source % 7 == 0 ? nil : "git",
            name: "project-\(source % count)",
            time: .init(created: base.timeIntervalSince1970 * 1000,
                        updated: base.addingTimeInterval(Double(index)).timeIntervalSince1970 * 1000,
                        active: nil),
            sandboxes: []
        )
    }
}

func legacyOrderedProjects(projects: [String: Project], sessions: [Session], activeIDs: Set<String>) -> [Project] {
    func runningSessions(in project: Project) -> [Session] {
        sessions
            .filter { $0.projectID == project.id && activeIDs.contains($0.id) }
            .sorted { $0.time.updated > $1.time.updated }
    }
    func ranksBelow(_ lhs: Project, than rhs: Project) -> Bool {
        let left = runningSessions(in: lhs).count
        let right = runningSessions(in: rhs).count
        if left != right { return left < right }
        let leftVCS = lhs.vcs?.isEmpty == false
        let rightVCS = rhs.vcs?.isEmpty == false
        if leftVCS != rightVCS { return !leftVCS }
        return lhs.lastActiveDate < rhs.lastActiveDate
    }
    return Dictionary(grouping: projects.values, by: \.canonical)
        .values
        .compactMap { records in records.max(by: ranksBelow) }
        .sorted { ranksBelow($1, than: $0) }
}

func syntheticChanges(_ count: Int) -> [FileChange] {
    let patch = (["@@ -1,20 +1,20 @@"] + (0..<40).map { "+line \($0)" }).joined(separator: "\n")
    return (0..<count).map { index in
        FileChange(
            file: "src/components/file-\(index % 300).swift",
            patch: patch,
            additions: 20,
            deletions: 3,
            status: index % 9 == 0 ? "added" : "modified",
            sessionID: "ses_\(index % 12)",
            sessionTitle: "Session \(index % 12)",
            messageID: "msg_\(index)",
            created: 1_700_000_000 + Double(index)
        )
    }
}

func syntheticFiles(_ count: Int) -> [ProjectFile] {
    (0..<count).map { index in
        ProjectFile(path: "Sources/Feature\(index % 40)/Sub\(index % 7)/Component\(index).swift",
                    status: index % 100 == 0 ? "modified" : nil)
    }
}

let sessions = syntheticSessions(1000, days: 365)
let stats = syntheticStats(days: 365)
let projects = syntheticProjects(80)
let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
let activeIDs = Set(sessions.prefix(20).map(\.id))
let changes = syntheticChanges(2000)
let files = syntheticFiles(20_000)
let messages = (0..<300).map { index in
    SessionMessage(
        id: "msg_\(index)",
        type: index % 3 == 0 ? "user" : "assistant",
        time: .init(created: 1_700_000_000 + Double(index) * 10, streamed: nil, completed: nil),
        text: "Prompt \(index)",
        content: [
            MessagePart(type: "text", id: "part_\(index)", text: "Response body \(index)", name: nil, state: nil, time: nil)
        ],
        model: nil,
        agent: nil,
        cost: nil,
        tokens: nil
    )
}

@main
struct PerfBenchmark {
    static func main() {
        // Warm up formatter/day caches.
        _ = UsageSeries.build(stats: stats, sessions: sessions, range: .year)
        _ = Fmt.grouped(1)

        print("--- OpenCodeBar performance benchmark ---")
        print(String(format: "UsageSeries year (1000 sessions, 365 days): %.3f ms/op",
                     measure(20) { _ = UsageSeries.build(stats: stats, sessions: sessions, range: .year) }))
        print(String(format: "UsageSeries all  (1000 sessions, 365 days): %.3f ms/op",
                     measure(20) { _ = UsageSeries.build(stats: stats, sessions: sessions, range: .all) }))
        print(String(format: "orderedProjects legacy (88 projects, 1000 sessions): %.3f ms/op",
                     measure(50) { _ = legacyOrderedProjects(projects: projectMap, sessions: sessions, activeIDs: activeIDs) }))
        let runningCounts = ProjectOrdering.runningCounts(sessions: sessions, activeIDs: activeIDs)
        print(String(format: "ProjectOrdering.ordered (88 projects, 1000 sessions): %.3f ms/op",
                     measure(50) { _ = ProjectOrdering.ordered(projects: projectMap, runningCounts: runningCounts) }))
        print(String(format: "FileChangeGroup.grouped (2000 changes): %.3f ms/op",
                     measure(30) { _ = FileChangeGroup.grouped(changes) }))
        print(String(format: "Fmt.grouped (50k calls): %.3f ms/op",
                     measure(10) { for index in 0..<50_000 { _ = Fmt.grouped(index) } }))
        print(String(format: "Project file filter, legacy 3 reads (20k files): %.3f ms/op",
                     measure(50) {
                         for _ in 0..<3 {
                             _ = files.filter {
                                 $0.path.localizedCaseInsensitiveContains("component19")
                             }
                         }
                     }))
        print(String(format: "Project file filter, computed once (20k files): %.3f ms/op",
                     measure(50) {
                         _ = files.filter {
                             $0.path.localizedCaseInsensitiveContains("component19")
                         }
                     }))
        print(String(format: "UsageSeries bucketed (365 -> 120): %.3f ms/op",
                     measure(50) {
                         let points = UsageSeries.build(stats: stats, sessions: sessions, range: .year)
                         _ = UsageSeries.bucketed(points, maxPoints: 120)
                     }))
        print(String(format: "Message sort (300 messages): %.3f ms/op",
                     measure(1000) { _ = MessageOrdering.mostRecentFirst(messages) }))
    }
}

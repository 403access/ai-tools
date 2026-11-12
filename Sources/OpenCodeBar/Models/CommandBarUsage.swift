import Foundation

/// One command-bar prompt and the assistant work it triggered.
struct CommandBarUsageEntry: Identifiable, Equatable, Sendable {
    let id: String
    let prompt: String
    let createdAt: Date
    let model: ModelRef?
    let cost: Double
    let tokens: TokenUsage
    let durationMilliseconds: Double?
    let outcome: String?
}

/// Usage for the persistent OpenCode conversation that backs the command bar.
/// The card still shows the session's normal totals; this shape only groups the
/// prompts so the Usage tab can label them separately from project work.
struct CommandBarUsage: Equatable, Sendable {
    let session: Session
    let model: ModelRef?
    let prompts: Int
    let cost: Double
    let tokens: TokenUsage
    let updated: Date
    let entries: [CommandBarUsageEntry]

    var title: String {
        let value = session.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Command bar" : value
    }
}

enum CommandBarUsageBuilder {
    /// Pairs each user prompt with the assistant messages that followed it and
    /// keeps the newest `limit` entries. Session totals come from the stats
    /// endpoint when available, because they survive a partial message cache.
    static func build(
        session: Session,
        stats: SessionStats?,
        messages: [SessionMessage],
        limit: Int = 5
    ) -> CommandBarUsage {
        let ordered = messages.sorted { lhs, rhs in
            if lhs.time.created != rhs.time.created {
                return lhs.time.created < rhs.time.created
            }
            return lhs.id < rhs.id
        }

        var entries: [CommandBarUsageEntry] = []
        var index = 0
        while index < ordered.count {
            let message = ordered[index]
            guard message.type == "user" else {
                index += 1
                continue
            }

            let prompt = message.promptText ?? "(empty prompt)"
            var cost = 0.0
            var tokens = TokenUsage.zero
            var model: ModelRef?
            var outcome: String?
            var firstStart: Double?
            var lastEnd: Double?
            var cursor = index + 1
            while cursor < ordered.count, ordered[cursor].type != "user" {
                let reply = ordered[cursor]
                if reply.type == "assistant" {
                    cost += reply.cost ?? 0
                    if let value = reply.tokens {
                        tokens = add(tokens, value)
                    }
                    if let value = reply.model { model = value }
                    if let value = reply.outcome, !value.isEmpty { outcome = value }
                    if firstStart == nil { firstStart = reply.time.created }
                    if let end = reply.time.completed ?? reply.time.streamed {
                        lastEnd = max(lastEnd ?? end, end)
                    }
                }
                cursor += 1
            }

            let duration = firstStart.flatMap { start in
                lastEnd.map { max($0 - start, 0) }
            }
            entries.append(
                CommandBarUsageEntry(
                    id: message.id,
                    prompt: prompt,
                    createdAt: message.time.createdDate,
                    model: model,
                    cost: cost,
                    tokens: tokens,
                    durationMilliseconds: duration,
                    outcome: outcome
                )
            )
            index = cursor
        }

        let entryCost = entries.reduce(0) { $0 + $1.cost }
        let entryTokens = entries.reduce(TokenUsage.zero) { add($0, $1.tokens) }
        let sessionTokens = session.tokens

        return CommandBarUsage(
            session: session,
            model: session.model ?? entries.last?.model,
            prompts: stats?.prompts ?? entries.count,
            cost: stats?.cost ?? (session.cost > 0 ? session.cost : entryCost),
            tokens: stats?.tokens
                ?? (sessionTokens.total > 0 ? sessionTokens : entryTokens),
            updated: session.time.updatedDate,
            entries: Array(entries.suffix(max(limit, 0)).reversed())
        )
    }

    private static func add(_ lhs: TokenUsage, _ rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            reasoning: lhs.reasoning + rhs.reasoning,
            cache: TokenUsage.Cache(
                read: lhs.cache.read + rhs.cache.read,
                write: lhs.cache.write + rhs.cache.write
            )
        )
    }
}

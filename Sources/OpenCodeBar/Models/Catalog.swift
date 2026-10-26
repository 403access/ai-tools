import Foundation

// MARK: - OpenCode model and agent catalogs

/// One model OpenCode can select. The service sends many more fields; the apps
/// only need an identity and a friendly name for pickers.
struct ModelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var modelID: String?
    var providerID: String
    var name: String?
    var enabled: Bool?
    var status: String?
    var variants: [Variant]?

    struct Variant: Codable, Hashable, Sendable {
        var id: String
        var name: String?
    }

    var displayName: String {
        let value = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? (modelID ?? id) : value
    }

    var isAvailable: Bool {
        guard enabled ?? true else { return false }
        return status == nil || status == "active"
    }

    func ref(variant: String? = nil) -> ModelRef {
        ModelRef(id: modelID ?? id, providerID: providerID, variant: variant)
    }

    var choice: ModelChoice {
        ModelChoice(providerID: providerID, modelID: modelID ?? id)
    }
}

/// Stable picker identity for a provider/model pair, without a variant.
struct ModelChoice: Hashable, Identifiable {
    var providerID: String
    var modelID: String

    var id: String { "\(providerID)/\(modelID)" }

    init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }

    init(_ ref: ModelRef) {
        self.init(providerID: ref.providerID, modelID: ref.id)
    }
}

/// One agent OpenCode can run.
struct AgentInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String?
    var mode: String?
    var hidden: Bool?
    var description: String?
    var model: ModelRef?

    var displayName: String {
        let value = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? id : value
    }

    /// Agents that can own a foreground turn.
    var isSelectable: Bool {
        guard hidden != true else { return false }
        return mode == nil || mode == "primary" || mode == "all"
    }
}

struct ModelsCatalogResponse: Decodable {
    var data: [ModelInfo]
}

struct ModelCatalogResponse: Decodable {
    var data: ModelInfo?
}

struct AgentsCatalogResponse: Decodable {
    var data: [AgentInfo]
}

// MARK: - Failed turns

/// The pieces needed to retry a failed turn in a forked session.
struct FailedTurn: Identifiable {
    /// The assistant or idle message that carries the error.
    var message: SessionMessage
    /// The user prompt that started the failed turn.
    var prompt: SessionMessage
    /// Settings actually used by the failed turn.
    var model: ModelRef?
    var agent: String?

    var id: String { message.id }
    var promptText: String? { prompt.promptText }
}

extension Array where Element == SessionMessage {
    /// Rows that should render in the conversation. Successful idle status
    /// messages are bookkeeping, and an assistant error with no content is
    /// hidden when the idle status right after it carries the same failure.
    func visibleForConversation() -> [SessionMessage] {
        enumerated().compactMap { index, message in
            guard message.isVisibleStatus else { return nil }
            if message.type == "assistant",
               let error = message.error,
               (message.content ?? []).isEmpty {
                let newer = index > 0 ? self[index - 1] : nil
                if newer?.error?.displayMessage == error.displayMessage {
                    return nil
                }
            }
            return message
        }
    }

    /// Finds a failure in the newest turn. Messages are ordered newest first,
    /// so only look at the leading rows; an old failure followed by a success
    /// should not keep offering a retry.
    func latestFailedTurn(lookback: Int = 4) -> FailedTurn? {
        guard let index = prefix(lookback).firstIndex(where: { $0.error != nil }) else {
            return nil
        }
        let message = self[index]

        guard let prompt = self[(index + 1)...].first(where: \.isUserLike),
              prompt.promptText != nil
        else { return nil }

        let assistant = self[index...].first(where: { $0.type == "assistant" })
        return FailedTurn(
            message: message,
            prompt: prompt,
            model: assistant?.model,
            agent: assistant?.agent
        )
    }
}

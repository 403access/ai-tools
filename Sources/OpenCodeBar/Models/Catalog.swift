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

/// How the model picker orders its list.
enum ModelSortOrder: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// One section per provider, models sorted by name inside it.
    case provider = "Provider"
    /// One flat A–Z list, ignoring providers.
    case name = "Name"

    var id: String { rawValue }
}

extension Array where Element == ModelInfo {
    /// Providers present in the list, alphabetically, for filter chips.
    var providerIDs: [String] {
        Set(map(\.providerID)).sorted()
    }

    /// Case-insensitive filter across the display name, model id and provider,
    /// optionally narrowed to one provider. The free-text query is ignored
    /// when it is blank so clearing the search restores the full list.
    func filteringModels(query: String, providerID: String?) -> [ModelInfo] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return filter { model in
            if let providerID, model.providerID != providerID { return false }
            guard !needle.isEmpty else { return true }
            return model.displayName.lowercased().contains(needle)
                || model.id.lowercased().contains(needle)
                || (model.modelID ?? "").lowercased().contains(needle)
                || model.providerID.lowercased().contains(needle)
        }
    }

    /// Alphabetical order used by the flat "Name" sort and inside each
    /// provider section.
    func sortedByDisplayName() -> [ModelInfo] {
        sorted {
            let result = $0.displayName.localizedStandardCompare($1.displayName)
            if result != .orderedSame { return result == .orderedAscending }
            return $0.providerID < $1.providerID
        }
    }

    /// Models folded into provider sections, preserving the display-name order
    /// inside each section. Empty providers are dropped.
    func groupedByProvider() -> [ModelProviderGroup] {
        providerIDs.compactMap { provider in
            let models = filter { $0.providerID == provider }.sortedByDisplayName()
            return models.isEmpty ? nil : ModelProviderGroup(providerID: provider, models: models)
        }
    }
}

/// One provider's slice of the model list, used by the searchable pickers.
struct ModelProviderGroup: Identifiable, Hashable, Sendable {
    var providerID: String
    var models: [ModelInfo]

    var id: String { providerID }
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

/// Where a retried prompt is sent. Continuing keeps one conversation; forking
/// copies the history up to the failed prompt into a new session first.
enum RetryDestination: String, CaseIterable, Identifiable, Sendable {
    case sameSession
    case newSession

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sameSession: return "This session"
        case .newSession: return "New fork"
        }
    }

    var explanation: String {
        switch self {
        case .sameSession:
            return "Sends the prompt here. The failed turn stays in this conversation."
        case .newSession:
            return "Copies the history before this prompt into a new session. The original session is unchanged."
        }
    }
}

/// The pieces needed to retry a failed turn in the same or a forked session.
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

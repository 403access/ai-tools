import Foundation

// MARK: - OpenCode model and agent catalogs

/// One model OpenCode can select. The service sends many more fields; the apps
/// keep identity and naming plus pricing and limits for picker badges.
struct ModelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var modelID: String?
    var providerID: String
    var name: String?
    var enabled: Bool?
    var status: String?
    var variants: [Variant]?
    /// Token pricing, when the service exposes it. Models with a zero input and
    /// output price are shown as free in the pickers.
    var cost: Cost? = nil
    /// Context and output limits used for compact capability badges.
    var limit: Limit? = nil

    struct Variant: Codable, Hashable, Sendable {
        var id: String
        var name: String?
    }

    /// Pricing tiers. OpenCode currently sends an array of tiers, while older
    /// services and fixtures use a single object, so decoding accepts both.
    struct Cost: Codable, Hashable, Sendable {
        var tiers: [Tier]

        struct Tier: Codable, Hashable, Sendable {
            var input: Double?
            var output: Double?
        }

        var input: Double? { tiers.first?.input }
        var output: Double? { tiers.first?.output }

        init(input: Double?, output: Double?) {
            tiers = [Tier(input: input, output: output)]
        }

        init(tiers: [Tier]) {
            self.tiers = tiers
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let tiers = try? container.decode([Tier].self) {
                self.tiers = tiers
            } else if let tier = try? container.decode(Tier.self) {
                self.tiers = [tier]
            } else {
                self.tiers = []
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(tiers)
        }

        var isFree: Bool {
            !tiers.isEmpty && tiers.allSatisfy { $0.input == 0 && $0.output == 0 }
        }
    }

    struct Limit: Codable, Hashable, Sendable {
        var context: Int?
        var output: Int?
    }

    var displayName: String {
        let value = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? (modelID ?? id) : value
    }

    var isAvailable: Bool {
        guard enabled ?? true else { return false }
        return status == nil || status == "active"
    }

    /// True when the provider publishes zero input and output pricing, or when
    /// the model identity carries an explicit free suffix.
    var isFree: Bool {
        if let cost, cost.isFree {
            return true
        }
        let identity = (modelID ?? id).lowercased()
        return identity.contains("-free") || identity.hasSuffix("/free")
    }

    /// Compact context-window label such as "200K" or "1M", when known.
    var contextLabel: String? {
        guard let context = limit?.context, context > 0 else { return nil }
        if context >= 1_000_000 {
            let millions = Double(context) / 1_000_000
            var label = String(format: "%.1f", millions)
            if label.hasSuffix(".0") {
                label.removeLast(2)
            }
            return "\(label)M"
        }
        if context >= 1_000 {
            let thousands = Double(context) / 1_000
            return thousands.rounded() == thousands
                ? "\(Int(thousands))K"
                : String(format: "%.0fK", thousands)
        }
        return "\(context)"
    }

    /// Non-active lifecycle states worth surfacing next to a model name.
    var statusBadge: String? {
        guard let status, status != "active" else { return nil }
        return status.capitalized
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

    /// Case- and accent-insensitive filter across the display name, model id,
    /// provider and variant names, optionally narrowed to one provider.
    ///
    /// Every whitespace-separated query token must match (so "openai 5" finds
    /// GPT-5), and a few shortcuts work as filters: `free`, `favorite`, and
    /// `provider:<id>`. A blank query restores the full list.
    func filteringModels(
        query: String,
        providerID: String?,
        favorites: Set<String> = [],
        favoritesOnly: Bool = false,
        freeOnly: Bool = false
    ) -> [ModelInfo] {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).searchNormalized }
            .filter { !$0.isEmpty }

        return filter { model in
            if let providerID, model.providerID != providerID { return false }
            let isFavorite = favorites.contains(model.choice.id)
            if favoritesOnly && !isFavorite { return false }
            if freeOnly && !model.isFree { return false }
            guard !tokens.isEmpty else { return true }

            let haystack = [
                model.displayName,
                model.id,
                model.modelID ?? "",
                model.providerID,
                (model.variants ?? []).compactMap(\.name).joined(separator: " "),
                (model.variants ?? []).map(\.id).joined(separator: " "),
            ]
            .joined(separator: " ")
            .searchNormalized
            let providerToken = model.providerID.searchNormalized

            return tokens.allSatisfy { token in
                if token == "free" || token == "is:free" { return model.isFree }
                if token == "favorite" || token == "favourite"
                    || token == "fav" || token == "starred" {
                    return isFavorite
                }
                if token.hasPrefix("provider:") || token.hasPrefix("p:") {
                    let name = token.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                    return providerToken.contains(name)
                }
                return haystack.contains(token)
            }
        }
    }

    /// Models marked as favorites, in the picker's normal name order.
    func favorites(in ids: Set<String>) -> [ModelInfo] {
        filter { ids.contains($0.choice.id) }.sortedByDisplayName()
    }

    /// The complement of `favorites(in:)`, preserving the caller's order.
    func excludingFavorites(in ids: Set<String>) -> [ModelInfo] {
        filter { !ids.contains($0.choice.id) }
    }

    /// Favorites first, then the remaining models. Used by the flat name sort.
    func favoritesFirst(in ids: Set<String>) -> [ModelInfo] {
        favorites(in: ids) + excludingFavorites(in: ids).sortedByDisplayName()
    }

    /// Models offered for a session, with unavailable entries removed.
    /// Providers stay grouped so the picker reads predictably.
    var availableForSelection: [ModelInfo] {
        filter(\.isAvailable).sorted {
            if $0.providerID != $1.providerID { return $0.providerID < $1.providerID }
            let result = $0.displayName.localizedStandardCompare($1.displayName)
            if result != .orderedSame { return result == .orderedAscending }
            return $0.id < $1.id
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

private extension String {
    /// Search key shared by the query and the model fields: lowercased, with
    /// accents removed and punctuation folded to spaces so "gpt-5" matches
    /// "GPT 5" and "sonnet-4.5".
    var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(
                of: #"[\s/_\-.]+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Persisted model-picker choices shared by the Mac and mobile apps.
///
/// Favorites are global, while the last selection is used to preselect the
/// model when a new session sheet opens. Both store provider and model ids so
/// they survive catalog reloads and app launches.
enum ModelPreferences {
    static let favoritesKey = "OpenCodeBar.favoriteModels"
    static let lastSelectionKey = "OpenCodeBar.lastModelSelection"

    struct LastSelection: Codable, Hashable, Sendable {
        var providerID: String
        var modelID: String
        var variant: String?

        var choice: ModelChoice {
            ModelChoice(providerID: providerID, modelID: modelID)
        }
    }

    static var favoriteIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
    }

    /// Adds or removes a favorite and returns the new state.
    @discardableResult
    static func toggleFavorite(_ model: ModelInfo) -> Bool {
        var ids = favoriteIDs
        let id = model.choice.id
        let isFavorite: Bool
        if ids.contains(id) {
            ids.remove(id)
            isFavorite = false
        } else {
            ids.insert(id)
            isFavorite = true
        }
        UserDefaults.standard.set(ids.sorted(), forKey: favoritesKey)
        return isFavorite
    }

    static var lastSelection: LastSelection? {
        guard let data = UserDefaults.standard.data(forKey: lastSelectionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(LastSelection.self, from: data)
    }

    /// Records the last model a picker chose so the next new session can start
    /// from it instead of OpenCode's default.
    static func rememberSelection(_ model: ModelInfo, variant: String?) {
        let choice = model.choice
        let selection = LastSelection(
            providerID: choice.providerID,
            modelID: choice.modelID,
            variant: variant
        )
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: lastSelectionKey)
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

import Combine
import Foundation

extension MobileStore {
    // MARK: - Detail data

    /// Keeps the on-demand caches bounded so opening many sessions or projects
    /// does not keep every message, patch and file list alive.
    func trimCache<T>(
        _ cache: inout [String: T],
        loadedAt: (T) -> Date?,
        limit: Int = 16,
        pinning key: String? = nil
    ) {
        guard cache.count > limit else { return }
        let kept = cache
            .sorted { (loadedAt($0.value) ?? .distantPast) > (loadedAt($1.value) ?? .distantPast) }
            .prefix(limit)
        var trimmed = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        if let key, let pinned = cache[key] { trimmed[key] = pinned }
        cache = trimmed
    }

    /// Newest cached messages, available before the network request finishes.
    func cachedMessages(for sessionID: String, limit: Int = 100) -> [SessionMessage] {
        database?.messages(for: sessionID, limit: limit) ?? []
    }

    /// Fetches messages from the hub and writes them to the local cache. When
    /// `since` is set, only messages at/after that timestamp are returned.
    func messages(
        for sessionID: String,
        limit: Int = 100,
        cursor: String? = nil,
        since: Double? = nil
    ) async throws -> SessionMessagesResponse {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        let response = try await api.sessionMessages(
            id: sessionID,
            limit: limit,
            cursor: cursor,
            since: since
        )
        database?.upsertMessages(response.data, for: sessionID)
        return response
    }

    /// Creates a session in a project directory. The caller decides when to
    /// navigate to it, since the mobile app owns its navigation path.
    func createSession(title: String?, directory: String) async throws -> Session {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        let session = try await api.createSession(title: title, directory: directory)
        sessions.insert(session, at: 0)
        history.insert(session, at: 0)
        database?.upsertSessions([session])
        rebuildDerived()
        await refreshLive()
        return session
    }

    /// Sends a prompt into an existing session. Running sessions queue the
    /// message by default so it does not interrupt the current turn.
    func promptSession(
        id: String,
        text: String,
        delivery: PromptDelivery? = nil
    ) async throws {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        try await api.promptSession(id: id, text: text, delivery: delivery)
        activeIDs.insert(id)
        rebuildDerived()
        await refreshLive()
        await loadPending(id, force: true)
    }

    /// Fetches the prompts a session has accepted but not delivered yet.
    func loadPending(_ sessionID: String, force: Bool = false) async {
        guard let api else { return }
        if sessionPending[sessionID]?.isLoading == true { return }
        if !force, let loaded = sessionPending[sessionID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 5 {
            return
        }
        defer { trimCache(&sessionPending, loadedAt: { $0.loadedAt }, pinning: sessionID) }

        var state = sessionPending[sessionID] ?? PendingState()
        state.isLoading = true
        state.error = nil
        sessionPending[sessionID] = state

        do {
            let items = try await api.sessionPending(id: sessionID)
            sessionPending[sessionID] = PendingState(items: items, loadedAt: Date())
        } catch {
            var failed = sessionPending[sessionID] ?? PendingState()
            failed.isLoading = false
            failed.loadedAt = Date()
            if Task.isCancelled {
                sessionPending[sessionID] = failed
                return
            }
            failed.error = message(for: error)
            sessionPending[sessionID] = failed
        }
    }

    /// Withdraws one queued prompt before the running turn consumes it.
    func cancelPending(_ sessionID: String, itemID: String) async throws {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        try await api.cancelPending(id: sessionID, pendingID: itemID)
        if var state = sessionPending[sessionID] {
            state.items.removeAll { $0.id == itemID }
            sessionPending[sessionID] = state
        }
    }
}

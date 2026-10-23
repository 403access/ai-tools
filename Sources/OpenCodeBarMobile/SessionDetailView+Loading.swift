import SwiftUI

extension SessionDetailView {
    // MARK: - Loading

    func loadLatest() async {
        guard !isFetchingLatest else { return }
        isFetchingLatest = true
        if messages.isEmpty {
            // Render the local cache immediately, then catch up with the hub.
            isLoading = true
            let cached = store.cachedMessages(for: sessionID, limit: 100)
            if !cached.isEmpty {
                messages = cached
                isLoading = false
            }
        }
        defer {
            isLoading = false
            isFetchingLatest = false
        }

        do {
            // The first page fills the view (and the cached gap); later
            // refreshes only need messages created since the newest one.
            let hasContent = !messages.isEmpty
            let limit = hasContent ? 30 : 100
            let since = loadedRemotePage && hasContent ? messages.first?.time.created : nil
            let response = try await store.messages(for: sessionID, limit: limit, since: since)
            guard !Task.isCancelled else { return }
            let fresh = response.data

            if since != nil {
                // Delta refresh: update matching rows and insert new ones, but
                // keep the older messages already loaded (or cached).
                var byID = Dictionary(
                    messages.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                for message in fresh { byID[message.id] = message }
                let merged = MessageOrdering.mostRecentFirst(Array(byID.values))
                if merged != messages { messages = merged }
            } else {
                let freshIDs = Set(fresh.map(\.id))
                let cutoff = fresh.map(\.time.created).min()
                let retained = messages.filter { message in
                    guard !freshIDs.contains(message.id), let cutoff else { return false }
                    return message.time.created < cutoff
                }

                let merged = MessageOrdering.mostRecentFirst(fresh + retained)
                if merged != messages { messages = merged }
                previousCursor = response.cursor?.previous
            }
            if since == nil { loadedRemotePage = true }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if messages.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func loadEarlier() async {
        guard let cursor = previousCursor, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        earlierError = nil
        defer { isLoadingEarlier = false }

        do {
            let response = try await store.messages(for: sessionID, limit: 100, cursor: cursor)
            guard !Task.isCancelled else { return }
            let existing = Set(messages.map(\.id))
            let older = response.data.filter { !existing.contains($0.id) }
            messages = MessageOrdering.mostRecentFirst(messages + older)
            previousCursor = response.cursor?.previous
        } catch {
            guard !Task.isCancelled else { return }
            earlierError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

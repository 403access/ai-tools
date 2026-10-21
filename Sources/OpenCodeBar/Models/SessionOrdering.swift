import Foundation

/// Shared "most recent first" ordering for feeds: sessions, chat messages and
/// file changes all put the newest item at the top.
enum SessionOrdering {
    /// Newest activity first, with stable tie-breaks so rows never shuffle
    /// between polls when two sessions share the same timestamp.
    static func mostRecentFirst(_ sessions: [Session]) -> [Session] {
        sessions.sorted { lhs, rhs in
            if lhs.time.updated != rhs.time.updated {
                return lhs.time.updated > rhs.time.updated
            }
            if lhs.time.created != rhs.time.created {
                return lhs.time.created > rhs.time.created
            }
            return lhs.id < rhs.id
        }
    }
}

enum MessageOrdering {
    /// Chat transcripts arrive newest-first from the hub; this keeps retained
    /// pages (and any fallback ordering) in the same shape.
    static func mostRecentFirst(_ messages: [SessionMessage]) -> [SessionMessage] {
        messages.sorted { lhs, rhs in
            if lhs.time.created != rhs.time.created {
                return lhs.time.created > rhs.time.created
            }
            return lhs.id > rhs.id
        }
    }
}

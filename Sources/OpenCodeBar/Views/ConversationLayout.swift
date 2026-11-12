import SwiftUI

/// How the session conversation is rendered. `cards` keeps the original
/// full-width card design; `chat` is a more compact, chat-bubble layout that
/// packs the same content into less vertical space.
enum ConversationLayout: String, CaseIterable, Identifiable {
    case cards
    case chat

    /// `@AppStorage` key so the choice is remembered across launches.
    static let defaultsKey = "chat.conversationLayout"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .chat: return "Chat"
        }
    }

    var icon: String {
        switch self {
        case .cards: return "square.stack.3d.up"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }

    /// Short explanation used by the Settings toggle.
    var settingDescription: String {
        switch self {
        case .cards:
            return "Each message sits in its own card with a header, border, and spacing."
        case .chat:
            return "Messages are rendered as compact chat bubbles that use less vertical space."
        }
    }
}

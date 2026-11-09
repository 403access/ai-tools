import Foundation
import SwiftUI

enum ChatTextRendering {
    static let renderMarkdownKey = "chat.renderMarkdown"

    /// Markdown rendering is enabled unless the user explicitly turned it off.
    static var rendersMarkdown: Bool {
        UserDefaults.standard.object(forKey: renderMarkdownKey) as? Bool ?? true
    }

    /// CommonMark treats a single newline as a soft break (often rendered as a
    /// space). Chat messages frequently use single newlines, so preserve them as
    /// hard breaks outside fenced code blocks.
    static func preservingLineBreaks(in markdown: String) -> String {
        var result = ""
        var index = markdown.startIndex
        var inFence = false
        var fenceMarker: Character = "`"
        var fenceCount = 0

        while index < markdown.endIndex {
            let lineEnd = markdown[index...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = String(markdown[index..<lineEnd])
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

            if inFence {
                result += line
                if isFenceClose(trimmed, marker: fenceMarker, count: fenceCount) {
                    inFence = false
                }
            } else if let fence = fenceOpen(trimmed) {
                inFence = true
                fenceMarker = fence.marker
                fenceCount = fence.count
                result += line
            } else {
                result += hardenLineBreaks(in: line)
            }

            if lineEnd < markdown.endIndex {
                result += "\n"
                index = markdown.index(after: lineEnd)
            } else {
                index = lineEnd
            }
        }

        return result
    }

    private static func fenceOpen(_ trimmed: Substring) -> (marker: Character, count: Int)? {
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        if marker == "`", trimmed.dropFirst(count).contains("`") { return nil }
        return (marker, count)
    }

    private static func isFenceClose(_ trimmed: Substring, marker: Character, count: Int) -> Bool {
        let closing = trimmed.prefix(while: { $0 == marker }).count
        guard closing >= count else { return false }
        return trimmed.dropFirst(closing).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func hardenLineBreaks(in line: String) -> String {
        guard !line.isEmpty else { return line }
        if line.hasSuffix("  ") || line.hasSuffix("\\") { return line }
        // Keep block-terminating blank lines natural; callers only pass single
        // physical lines. Adding a hard break preserves visible line breaks in
        // chat without collapsing them into spaces.
        return line + "  "
    }
}

/// Renders chat message text as Markdown when enabled in settings, otherwise as
/// plain text. Uses SwiftUI's native attributed Markdown support.
struct ChatText: View {
    let text: String
    @AppStorage(ChatTextRendering.renderMarkdownKey) private var rendersMarkdown = true

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if rendersMarkdown, let attributed = try? AttributedString(
            markdown: ChatTextRendering.preservingLineBreaks(in: text),
            options: .init(interpretedSyntax: .full)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}



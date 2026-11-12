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

// MARK: - Markdown block model

/// One structural block of a Markdown document, in source order. `quote` nests
/// further blocks so blockquotes can contain paragraphs, lists, and code.
enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
    case list(ordered: Bool, items: [MarkdownListItem])
    indirect case quote([MarkdownBlock])
    case table(MarkdownTable)
    case rule
}

/// A single list item. Only its inline Markdown text is kept; nested lists are
/// rendered as continuation lines rather than a separate structure.
struct MarkdownListItem {
    var text: String
}

/// A GFM table: header cells, the per-column alignment read from the separator
/// row, and the data rows.
struct MarkdownTable {
    var headers: [String]
    var alignments: [Alignment]
    var rows: [[String]]
}

// MARK: - Markdown parser

/// A small line-based Markdown parser that splits a message into the blocks the
/// chat renderer understands. It is intentionally conservative: anything it
/// does not recognise stays as a paragraph, so plain prose is never mangled.
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if let fence = fenceOpen(trimmed) {
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if isFenceClose(t, marker: fence.marker, count: fence.count) {
                        i += 1
                        break
                    }
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: fence.language, code: code.joined(separator: "\n")))
                continue
            }

            if isRule(trimmed) {
                blocks.append(.rule)
                i += 1
                continue
            }

            if let heading = heading(trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(">") {
                        quote.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else if t.isEmpty {
                        quote.append("")
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.quote(parse(quote.joined(separator: "\n"))))
                continue
            }

            if i + 1 < lines.count,
               trimmed.contains("|"),
               isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                let parsed = parseTable(lines, headerIndex: i)
                blocks.append(.table(parsed.table))
                i = parsed.endIndex
                continue
            }

            if let list = parseList(lines, start: i) {
                blocks.append(.list(ordered: list.ordered, items: list.items))
                i = list.end
                continue
            }

            var paragraph: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if isBlockStart(t) { break }
                if i + 1 < lines.count,
                   t.contains("|"),
                   isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                    break
                }
                paragraph.append(l)
                i += 1
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            }
        }

        return blocks
    }

    /// True when the text contains anything beyond plain paragraphs — tables,
    /// code fences, lists, headings, quotes, or rules — that needs block-level
    /// rendering.
    static func hasRichBlocks(_ text: String) -> Bool {
        parse(text).contains { block in
            if case .paragraph = block { return false }
            return true
        }
    }

    // MARK: Block detection

    static func isBlockStart(_ trimmed: String) -> Bool {
        if fenceOpen(trimmed) != nil { return true }
        if isRule(trimmed) { return true }
        if heading(trimmed) != nil { return true }
        if trimmed.hasPrefix(">") { return true }
        if listMarker(trimmed) != nil { return true }
        return false
    }

    static func fenceOpen(_ trimmed: String) -> (marker: Character, count: Int, language: String?)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        if first == "`", trimmed.dropFirst(count).contains("`") { return nil }
        let language = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
        return (first, count, language.isEmpty ? nil : language)
    }

    static func isFenceClose(_ trimmed: String, marker: Character, count: Int) -> Bool {
        let closing = trimmed.prefix(while: { $0 == marker }).count
        guard closing >= count else { return false }
        return trimmed.dropFirst(closing).allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
        guard compact.count >= 3, let first = compact.first else { return false }
        guard first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    static func heading(_ trimmed: String) -> (level: Int, text: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        let level = trimmed.prefix(while: { $0 == "#" }).count
        guard level <= 6 else { return nil }
        let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    static func listMarker(_ trimmed: String) -> (ordered: Bool, content: String)? {
        for prefix in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(prefix) {
                return (false, String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
            }
        }

        let digits = trimmed.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard let first = rest.first, first == "." || first == ")" else { return nil }
        let content = rest.dropFirst()
        guard content.isEmpty || content.first == " " || content.first == "\t" else { return nil }
        return (true, String(content).trimmingCharacters(in: .whitespaces))
    }

    // MARK: Lists

    static func parseList(
        _ lines: [String],
        start: Int
    ) -> (ordered: Bool, items: [MarkdownListItem], end: Int)? {
        var i = start
        var items: [MarkdownListItem] = []
        var ordered = false
        var sawMarker = false
        var current: [String] = []

        func flush() {
            if !current.isEmpty {
                items.append(MarkdownListItem(text: current.joined(separator: "\n")))
                current = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = listMarker(trimmed) {
                if !sawMarker { ordered = marker.ordered; sawMarker = true }
                flush()
                current.append(marker.content)
                i += 1
            } else if trimmed.isEmpty {
                i += 1
                break
            } else if line.hasPrefix(" ") || line.hasPrefix("\t") {
                current.append(trimmed)
                i += 1
            } else {
                break
            }
        }
        flush()

        guard !items.isEmpty else { return nil }
        return (ordered, items, i)
    }

    // MARK: Tables

    static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("-") else { return false }
        let cells = splitTableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    static func parseTable(
        _ lines: [String],
        headerIndex: Int
    ) -> (table: MarkdownTable, endIndex: Int) {
        let headers = splitTableCells(lines[headerIndex])
        let separators = splitTableCells(lines[headerIndex + 1])
        let alignments = separators.map(alignment)

        var rows: [[String]] = []
        var i = headerIndex + 2
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty || !t.contains("|") { break }
            rows.append(splitTableCells(lines[i]))
            i += 1
        }

        let table = MarkdownTable(headers: headers, alignments: alignments, rows: rows)
        return (table, i)
    }

    static func alignment(_ separatorCell: String) -> Alignment {
        let left = separatorCell.hasPrefix(":")
        let right = separatorCell.hasSuffix(":")
        if left && right { return .center }
        if right { return .trailing }
        return .leading
    }

    /// Splits a table row on `|`, honouring `\|` escapes, and drops the empty
    /// leading/trailing cells produced by a row's outer pipes.
    static func splitTableCells(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\\" {
                let next = line.index(after: i)
                if next < line.endIndex {
                    current.append(line[next])
                    i = next
                } else {
                    current.append(ch)
                }
            } else if ch == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        cells.append(current)

        let trimmed = cells.map { $0.trimmingCharacters(in: .whitespaces) }
        var start = trimmed.startIndex
        var end = trimmed.endIndex
        if end > start, trimmed[start].isEmpty { start += 1 }
        if end > start, trimmed[end - 1].isEmpty { end -= 1 }
        return Array(trimmed[start..<end])
    }
}

// MARK: - Renderer

/// Renders a parsed Markdown document as a stack of SwiftUI views. Paragraphs
/// and other inline text reuse SwiftUI's native attributed Markdown, while
/// tables, code fences, lists, headings, quotes, and rules get their own views.
struct MarkdownBody: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(headingFont(level))
        case .paragraph(let text):
            inline(text)
        case .code(_, let code):
            codeBlock(code)
        case .list(let ordered, let items):
            listView(ordered: ordered, items: items)
        case .quote(let blocks):
            quoteView(blocks)
        case .table(let table):
            tableView(table)
        case .rule:
            Divider().padding(.vertical, 2)
        }
    }

    // MARK: Inline

    private func inline(_ markdown: String) -> Text {
        let prepared = ChatTextRendering.preservingLineBreaks(in: markdown)
        if let attributed = try? AttributedString(
            markdown: prepared,
            options: .init(interpretedSyntax: .full)
        ) {
            return Text(attributed)
        }
        return Text(markdown)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 16, weight: .bold)
        case 2: return .system(size: 14, weight: .bold)
        case 3: return .system(size: 12.5, weight: .semibold)
        default: return .system(size: 11.5, weight: .semibold)
        }
    }

    // MARK: Blocks

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 10, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }

    private func listView(ordered: Bool, items: [MarkdownListItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .trailing)
                    inline(item.text)
                }
            }
        }
    }

    private func quoteView(_ blocks: [MarkdownBlock]) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 3)
            }
            .foregroundStyle(.secondary)
        )
    }

    private func tableView(_ table: MarkdownTable) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tableRow(table.headers, alignments: table.alignments, bold: true)
            Divider().padding(.vertical, 3)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                tableRow(row, alignments: table.alignments, bold: false)
                if index < table.rows.count - 1 {
                    Divider().opacity(0.35).padding(.vertical, 2)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func tableRow(_ cells: [String], alignments: [Alignment], bold: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                tableCell(cell, alignment: columnAlignment(index, alignments: alignments), bold: bold)
            }
        }
    }

    @ViewBuilder
    private func tableCell(_ cell: String, alignment: Alignment, bold: Bool) -> some View {
        if bold {
            inline(cell)
                .bold()
                .frame(maxWidth: .infinity, alignment: alignment)
        } else {
            inline(cell)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func columnAlignment(_ index: Int, alignments: [Alignment]) -> Alignment {
        guard index < alignments.count else { return .leading }
        return alignments[index]
    }
}

/// Renders chat message text as Markdown when enabled in settings, otherwise as
/// plain text. Plain prose keeps the single-`Text` path so line spacing and
/// truncation behave as before; richer content (tables, code, lists, headings)
/// falls back to the block renderer.
struct ChatText: View {
    let text: String
    @AppStorage(ChatTextRendering.renderMarkdownKey) private var rendersMarkdown = true

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if rendersMarkdown {
            if MarkdownParser.hasRichBlocks(text) {
                MarkdownBody(text: text)
            } else {
                plainText
            }
        } else {
            Text(text)
        }
    }

    @ViewBuilder
    private var plainText: some View {
        if let attributed = try? AttributedString(
            markdown: ChatTextRendering.preservingLineBreaks(in: text),
            options: .init(interpretedSyntax: .full)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}

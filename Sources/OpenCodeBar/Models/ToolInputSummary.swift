import Foundation

/// Turns a tool's JSON input into a one-line summary for the Live row.
enum ToolInputSummary {
    static func text(name: String, input: JSONValue?, directory: String?) -> String? {
        guard let input, case .object(let fields) = input else { return nil }
        let lowered = name.lowercased()
        if lowered == "todowrite" || lowered == "todo" { return nil }

        for key in ["command", "description", "filePath", "path", "pattern", "query", "url"] {
            guard let value = fields[key]?.stringValue, !value.isEmpty else { continue }
            return shorten(value, directory: directory)
        }
        return nil
    }

    private static func shorten(_ value: String, directory: String?) -> String {
        var text = value.replacingOccurrences(of: "\n", with: " ")
        if let directory, !directory.isEmpty, text.hasPrefix(directory + "/") {
            text = String(text.dropFirst(directory.count + 1))
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.count > 220 {
            text = String(text.prefix(220)) + "…"
        }
        return text
    }
}

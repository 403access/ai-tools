import Foundation

extension SessionActivity {
    // MARK: - Helpers

    static func appended(_ delta: String?, to detail: String?) -> String? {
        guard let delta, !delta.isEmpty else { return detail }
        return tail((detail ?? "") + delta)
    }

    /// Keeps enough text for a readable tail without holding a whole response.
    static func tail(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let limit = 1_200
        if text.count <= limit { return text }
        return String(text.suffix(limit))
    }

    static func date(millis: Double) -> Date {
        Date(timeIntervalSince1970: millis / 1000)
    }

    static func errorText(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        if case .object(let fields) = value {
            for key in ["message", "error", "reason", "detail"] {
                if let text = fields[key]?.stringValue, !text.isEmpty { return text }
            }
        }
        let text = value.compactDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func todos(from input: JSONValue?) -> [Todo]? {
        guard case .object(let fields)? = input,
              case .array(let items)? = fields["todos"]
        else { return nil }

        let todos = items.compactMap { item -> Todo? in
            guard case .object(let fields) = item,
                  let content = fields["content"]?.stringValue,
                  !content.isEmpty
            else { return nil }
            return Todo(content: content, status: fields["status"]?.stringValue ?? "pending")
        }
        return todos
    }
}

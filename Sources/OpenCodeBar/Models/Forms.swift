import Foundation

// MARK: - Forms

/// A value accepted by a form field. Choice and multi-choice fields use
/// strings; multi-select answers are sent as an array of strings.
enum FormValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case strings([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String].self) {
            self = .strings(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported form value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .strings(let values): try container.encode(values)
        }
    }

    /// One-line rendering used by completed-question summaries.
    var displayText: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "Yes" : "No"
        case .strings(let values): return values.joined(separator: ", ")
        }
    }
}

/// One selectable answer offered by a question.
struct FormOption: Decodable, Equatable, Hashable, Sendable, Identifiable {
    var value: String
    var label: String
    var description: String?

    var id: String { value }
}

/// One form field. The `question` tool encodes each question as a field keyed
/// `q0`, `q1`, …, with `title` carrying the short header and `description`
/// carrying the question itself.
struct FormField: Decodable, Equatable, Sendable, Identifiable {
    var key: String
    var type: String
    var title: String?
    var description: String?
    var required: Bool?
    var hidden: Bool?
    var options: [FormOption]?
    var custom: Bool?
    var minItems: Int?
    var maxItems: Int?
    var defaultValue: JSONValue?

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, type, title, description, required, hidden, options, custom
        case minItems, maxItems
        case defaultValue = "default"
    }

    var isMultiple: Bool { type == "multiselect" }
    var isChoice: Bool { !(options ?? []).isEmpty }
    var allowsCustom: Bool { custom == true }
    var displayTitle: String {
        let value = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Question" : value
    }
    var displayQuestion: String {
        let value = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? displayTitle : value
    }
}

/// A pending form exposed by OpenCode. The `question` tool creates one form per
/// call, with metadata linking it back to the tool part in the conversation.
struct FormInfo: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var sessionID: String
    var title: String
    var metadata: JSONValue?
    var fields: [FormField]

    var questions: [FormField] {
        fields.filter { !($0.hidden ?? false) }
    }

    /// The tool part that opened this form, when the form came from the
    /// `question` tool.
    var toolPartID: String? {
        toolMetadata?["id"]?.stringValue
    }

    var toolMessageID: String? {
        toolMetadata?["messageID"]?.stringValue
    }

    /// `metadata.kind == "question"` identifies forms owned by the question
    /// tool; other forms (MCP elicitation, demos) use different metadata.
    var isQuestionForm: Bool {
        guard case .object(let metadata)? = metadata else { return false }
        return metadata["kind"]?.stringValue == "question"
    }

    private var toolMetadata: [String: JSONValue]? {
        guard case .object(let metadata)? = metadata,
              case .object(let tool)? = metadata["tool"]
        else { return nil }
        return tool
    }
}

struct FormListResponse: Decodable {
    var data: [FormInfo]
}

// MARK: - Question tool parts

extension MessagePart {
    /// Questions requested by this `question` tool call. Available before the
    /// matching pending form loads, so the card can show what is being asked.
    var questionPrompts: [QuestionPrompt] {
        guard let input = state?.input,
              case .object(let fields) = input,
              case .array(let rawQuestions)? = fields["questions"]
        else { return [] }

        return rawQuestions.compactMap { raw in
            guard case .object(let question) = raw else { return nil }
            let header = question["header"]?.stringValue ?? "Question"
            let text = question["question"]?.stringValue
                ?? question["header"]?.stringValue
                ?? "Question"
            let options: [FormOption] = {
                guard case .array(let rawOptions)? = question["options"] else { return [] }
                return rawOptions.compactMap { rawOption in
                    guard case .object(let option) = rawOption,
                          let label = option["label"]?.stringValue
                    else { return nil }
                    return FormOption(
                        value: option["value"]?.stringValue ?? label,
                        label: label,
                        description: option["description"]?.stringValue
                    )
                }
            }()
            return QuestionPrompt(
                header: header,
                question: text,
                options: options,
                multiple: question["multiple"]?.boolValue ?? false,
                custom: question["custom"]?.boolValue ?? true
            )
        }
    }

    /// Answers the question tool recorded on its result.
    var questionAnswers: [[String]] {
        guard case .object(let metadata)? = state?.metadata,
              case .array(let answers)? = metadata["answers"]
        else { return [] }
        return answers.map { answer in
            guard case .array(let values) = answer else { return [] }
            return values.compactMap(\.stringValue)
        }
    }

    /// Cancellation reason recorded when the user dismissed a question form.
    var questionCancellation: String? {
        guard case .object(let metadata)? = state?.metadata else { return nil }
        return metadata["cancelled"]?.stringValue
            ?? metadata["message"]?.stringValue
    }
}

/// A question extracted from the tool input, used to render instantly while
/// the pending form is still loading.
struct QuestionPrompt: Equatable, Hashable, Sendable {
    var header: String
    var question: String
    var options: [FormOption]
    var multiple: Bool
    var custom: Bool
}

extension JSONValue {
    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

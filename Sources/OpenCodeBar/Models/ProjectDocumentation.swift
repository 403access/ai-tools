import Foundation

// MARK: - Project documentation

/// One project change derived from a prompt. The entry keeps the task and
/// session that produced it, so the Docs tab can link back to the work instead
/// of showing an anonymous changelog.
struct ProjectFeatureDoc: Decodable, Identifiable, Hashable, Sendable {
    enum Action: String, Codable, CaseIterable, Sendable {
        case new
        case update
        case remove

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Action(rawValue: raw) ?? .update
        }

        var title: String {
            switch self {
            case .new: return "New"
            case .update: return "Updated"
            case .remove: return "Removed"
            }
        }

        var icon: String {
            switch self {
            case .new: return "plus.circle.fill"
            case .update: return "pencil.circle.fill"
            case .remove: return "minus.circle.fill"
            }
        }
    }

    enum Kind: String, Codable, Sendable {
        case product
        case technical

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .technical
        }
    }

    var id: String
    var projectID: String
    var sessionID: String
    var taskTitle: String
    var title: String
    var detail: String
    var action: Action
    var kind: Kind
    var category: String
    var categoryTitle: String
    var labels: [TaskLabel]
    var createdAt: Double
    var updatedAt: Double

    var createdDate: Date { Date(timeIntervalSince1970: createdAt / 1000) }
    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
}

/// The living project brief on a project's Docs tab. Description, mission and
/// vision are editable; the feature sections are generated from prompts sent
/// through the hub.
struct ProjectDocumentation: Decodable, Hashable, Sendable {
    var projectID: String
    var description: String
    var mission: String
    var vision: String
    var productFeatures: [ProjectFeatureDoc]
    var technicalFeatures: [ProjectFeatureDoc]
    var updatedAt: Double

    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt / 1000) }

    var featureCount: Int { productFeatures.count + technicalFeatures.count }
}

struct ProjectDocumentationResponse: Decodable, Sendable {
    var data: ProjectDocumentation
}

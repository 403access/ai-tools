import Foundation

/// A repository visible to the hub's GitHub login, used by the New Session
/// clone flow. The hub marks repositories that already have a project folder.
struct GitHubRepository: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var fullName: String
    var owner: String
    var url: String
    var cloneURL: String
    var defaultBranch: String?
    var isPrivate: Bool
    var summary: String?
    /// Milliseconds since the epoch.
    var updatedAt: Double?
    var isArchived: Bool
    var isFork: Bool
    /// Hub folder that already contains this repository, when one exists.
    var clonedDirectory: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName
        case owner
        case url
        case cloneURL
        case defaultBranch
        case isPrivate = "private"
        case summary = "description"
        case updatedAt
        case isArchived = "archived"
        case isFork = "fork"
        case clonedDirectory
    }

    /// Repositories that are already checked out on the hub are shown but
    /// cannot be picked again.
    var isCloned: Bool { clonedDirectory != nil }

    var updatedDate: Date? {
        updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// Text a search should match: the repo name, owner, description, and the
    /// existing folder when there is one.
    var searchText: String {
        [fullName, summary ?? "", clonedDirectory ?? ""].joined(separator: " ")
    }
}

struct GitHubRepositoriesResponse: Decodable {
    var data: [GitHubRepository]
}

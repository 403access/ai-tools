import Foundation

// MARK: - Project scripts

/// One high-level task declared by a project manifest, such as an npm script
/// or a Makefile target. `command` is the invocation shown to the user.
struct ProjectScript: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var command: String
    var source: String
    var tool: String
    var detail: String?
    var description: String?

    var id: String { "\(source):\(name)" }
}

/// Scripts discovered in a project's root manifests, grouped by source.
struct ProjectScripts: Decodable, Hashable, Sendable {
    var scripts: [ProjectScript]
    var generatedAt: Double

    var generatedDate: Date { Date(timeIntervalSince1970: generatedAt / 1000) }
}

struct ProjectScriptsResponse: Decodable {
    var data: ProjectScripts?
}

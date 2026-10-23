import Foundation

// MARK: - Token usage

struct TokenUsage: Codable, Hashable, Sendable {
    var input: Double
    var output: Double
    var reasoning: Double
    var cache: Cache

    struct Cache: Codable, Hashable, Sendable {
        var read: Double
        var write: Double
    }

    static let zero = TokenUsage(input: 0, output: 0, reasoning: 0, cache: .init(read: 0, write: 0))

    /// Tokens generated/consumed by the model itself (excludes cache traffic).
    var generated: Double { input + output + reasoning }
    /// Everything, including cache reads and writes.
    var total: Double { generated + cache.read + cache.write }
}

// MARK: - Model reference

struct ModelRef: Codable, Hashable, Sendable {
    var id: String
    var providerID: String
    var variant: String?

    var label: String {
        if let variant, variant != "default" {
            return "\(id) · \(variant)"
        }
        return id
    }
}

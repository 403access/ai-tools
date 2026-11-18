import Foundation

/// One MCP server entry from an OpenCode config file.
struct MCPServerInfo: Identifiable, Equatable {
    enum Scope: String, Equatable {
        case global = "Global"
        case project = "Project"
    }

    let name: String
    let type: String
    let detail: String
    let scope: Scope
    let sourcePath: String

    var id: String { "\(sourcePath)|\(name)" }

    var isOpenCodeBar: Bool {
        name.caseInsensitiveCompare("opencodebar") == .orderedSame
    }
}

/// MCP servers discovered in OpenCode's global config and the checkout that
/// contains the hub. Settings only reads these files; OpenCode remains the owner
/// of the configuration.
struct MCPConfigurationSnapshot {
    let servers: [MCPServerInfo]
    let configFiles: [URL]
    let errors: [String]

    static let empty = MCPConfigurationSnapshot(servers: [], configFiles: [], errors: [])

    var isOpenCodeBarRegistered: Bool {
        servers.contains(where: \.isOpenCodeBar)
    }
}

enum MCPConfiguration {
    /// Reads `opencode.json`/`opencode.jsonc` from both the global config folder
    /// and the repository checkout. Entries are returned in source order with
    /// global servers first.
    static func load(
        globalDirectory: URL = ServiceDiscovery.configDir(),
        repositoryDirectory: URL? = HubLauncher.serverDirectory()?.deletingLastPathComponent(),
    ) -> MCPConfigurationSnapshot {
        var servers: [MCPServerInfo] = []
        var configFiles: [URL] = []
        var errors: [String] = []

        var seen: Set<String> = []
        func read(_ url: URL, scope: MCPServerInfo.Scope) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            guard FileManager.default.fileExists(atPath: path) else { return }
            configFiles.append(url)
            do {
                servers.append(contentsOf: try parse(url: url, scope: scope))
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        for name in ["opencode.json", "opencode.jsonc"] {
            read(globalDirectory.appendingPathComponent(name), scope: .global)
        }

        if let repositoryDirectory {
            for name in ["opencode.json", "opencode.jsonc"] {
                read(repositoryDirectory.appendingPathComponent(name), scope: .project)
            }
            read(
                repositoryDirectory
                    .appendingPathComponent(".opencode", isDirectory: true)
                    .appendingPathComponent("opencode.json"),
                scope: .project,
            )
        }

        return MCPConfigurationSnapshot(
            servers: servers.sorted { left, right in
                if left.scope != right.scope { return left.scope == .global }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            },
            configFiles: configFiles,
            errors: errors,
        )
    }

    /// Parses one OpenCode config. Supports `mcp.servers`, a direct `mcp` map,
    /// and the `mcpServers` spelling used by other MCP clients.
    static func parse(url: URL, scope: MCPServerInfo.Scope) throws -> [MCPServerInfo] {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let object = try decodeObject(text)
        return servers(from: object, sourcePath: url.path, scope: scope)
    }

    static func servers(
        from object: [String: Any],
        sourcePath: String,
        scope: MCPServerInfo.Scope,
    ) -> [MCPServerInfo] {
        let mcp = object["mcp"] as? [String: Any]
        let explicit = mcp?["servers"] as? [String: Any]
        let topLevel = object["mcpServers"] as? [String: Any]
        let map = explicit ?? topLevel ?? directMap(mcp)

        return (map ?? [:]).compactMap { name, raw in
            guard let config = raw as? [String: Any] else { return nil }
            let type = normalizedType(config)
            return MCPServerInfo(
                name: name,
                type: type,
                detail: detail(config, type: type),
                scope: scope,
                sourcePath: sourcePath,
            )
        }
    }

    // MARK: - Decoding

    private static func decodeObject(_ text: String) throws -> [String: Any] {
        if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            return object
        }
        let stripped = stripComments(text)
        guard let object = try JSONSerialization.jsonObject(
            with: Data(stripTrailingCommas(stripped).utf8)
        ) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    /// A small JSONC scanner: removes `//` and `/* … */` comments without
    /// touching URLs or other strings. OpenCode accepts JSONC, and hand-edited
    /// configs often carry comments.
    static func stripComments(_ input: String) -> String {
        var output = String()
        output.reserveCapacity(input.count)
        var index = input.startIndex
        var inString = false
        var escaped = false
        var inLineComment = false
        var inBlockComment = false

        while index < input.endIndex {
            let character = input[index]
            let next = input.index(after: index)

            if inLineComment {
                if character == "\n" || character == "\r" {
                    inLineComment = false
                    output.append(character)
                }
                index = next
                continue
            }

            if inBlockComment {
                if character == "*", next < input.endIndex, input[next] == "/" {
                    inBlockComment = false
                    index = input.index(after: next)
                } else {
                    index = next
                }
                continue
            }

            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = next
                continue
            }

            if character == "\"" {
                inString = true
                output.append(character)
                index = next
                continue
            }

            if character == "/", next < input.endIndex {
                let following = input[next]
                if following == "/" {
                    inLineComment = true
                    index = input.index(after: next)
                    continue
                }
                if following == "*" {
                    inBlockComment = true
                    index = input.index(after: next)
                    continue
                }
            }

            output.append(character)
            index = next
        }

        return output
    }

    /// JSONC also permits a trailing comma before a closing brace or bracket.
    /// Remove only commas outside strings that are followed by `}` or `]`.
    static func stripTrailingCommas(_ input: String) -> String {
        var output = String()
        output.reserveCapacity(input.count)
        var index = input.startIndex
        var inString = false
        var escaped = false

        while index < input.endIndex {
            let character = input[index]
            let next = input.index(after: index)

            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = next
                continue
            }

            if character == "\"" {
                inString = true
                output.append(character)
                index = next
                continue
            }

            if character == "," {
                var lookahead = next
                while lookahead < input.endIndex, input[lookahead].isWhitespace {
                    lookahead = input.index(after: lookahead)
                }
                if lookahead < input.endIndex,
                   input[lookahead] == "}" || input[lookahead] == "]" {
                    index = next
                    continue
                }
            }

            output.append(character)
            index = next
        }

        return output
    }

    /// `mcp` without a nested `servers` map is accepted by some configs. Only
    /// treat it as a map when every value is an object with a transport shape.
    private static func directMap(_ mcp: [String: Any]?) -> [String: Any]? {
        guard let mcp, !mcp.isEmpty else { return nil }
        let looksLikeServers = mcp.values.allSatisfy { value in
            guard let config = value as? [String: Any] else { return false }
            return config["command"] != nil || config["url"] != nil || config["type"] != nil
        }
        return looksLikeServers ? mcp : nil
    }

    private static func normalizedType(_ config: [String: Any]) -> String {
        if let type = config["type"] as? String, !type.isEmpty {
            return type
        }
        if config["url"] is String { return "remote" }
        if config["command"] != nil { return "local" }
        return "unknown"
    }

    private static func detail(_ config: [String: Any], type: String) -> String {
        if let command = config["command"] as? [String], !command.isEmpty {
            return command.joined(separator: " ")
        }
        if let url = config["url"] as? String, !url.isEmpty {
            return url
        }
        if let command = config["command"] as? String, !command.isEmpty {
            return command
        }
        return type == "remote" ? "Remote MCP server" : "Local MCP server"
    }
}
import Foundation

extension HubAPI {
    // MARK: - Endpoints

    func serverInfo() async throws -> ServerInfo {
        try await get("/api/info")
    }

    func health() async throws -> HubHealthResponse {
        try await get("/api/health")
    }

    /// Full snapshot of the machine running the hub: OS, CPU, memory, disks,
    /// network, battery, installed apps, Homebrew, toolchains, processes and
    /// more. The hub caches the expensive sections, so this is safe to poll.
    func systemInfo(force: Bool = false) async throws -> SystemInfo {
        let response: SystemInfoEnvelope = try await get(
            force ? "/api/system?refresh=1" : "/api/system"
        )
        return response.data
    }

    /// Mac and iOS apps known to the hub, including which ones are live now.
    func devices() async throws -> [ConnectedDevice] {
        let response: DevicesResponse = try await get("/api/devices")
        return response.data
    }

    /// Current hub behaviour, including the event update throttle.
    func settings() async throws -> ServerSettings {
        let response: ServerSettingsResponse = try await get("/api/settings")
        return response.data
    }

    /// Changes the coalescing window for updates sent to the apps. The hub
    /// applies it immediately and persists it for the next launch.
    func updateSettings(eventThrottleMs: Int) async throws -> ServerSettings {
        let body = try JSONEncoder().encode(["eventThrottleMs": eventThrottleMs])
        let data = try await send("/api/settings", method: "PATCH", body: body)
        do {
            return try Self.decoder.decode(ServerSettingsResponse.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Restarts the hub process. The connection may drop briefly while it
    /// rebinds its port.
    func restartServer() async throws {
        _ = try await send("/api/server/restart", method: "POST")
    }

    // MARK: - Host files

    /// Lists one folder on the machine running the hub.
    func hostFiles(path: String) async throws -> HostDirectory {
        let response: HostDirectoryEnvelope = try await get(Self.pathQuery("/api/files", path: path))
        return response.data
    }

    /// Text or image metadata for one host file.
    func hostFileContent(path: String) async throws -> HostFileContent {
        let response: HostFileContentEnvelope = try await get(
            Self.pathQuery("/api/files/content", path: path)
        )
        return response.data
    }

    /// Raw bytes of one host file, used for image previews.
    func hostFileData(path: String) async throws -> Data {
        try await send(Self.pathQuery("/api/files/raw", path: path))
    }

    private static func pathQuery(_ endpoint: String, path: String) -> String {
        var components = URLComponents()
        components.path = endpoint
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.string ?? endpoint
    }

    func activeSessionIDs() async throws -> [String] {
        let response: ActiveSessionsResponse = try await get("/api/session/active")
        return Array(response.data.keys)
    }

    func sessions(limit: Int = 60) async throws -> [Session] {
        let response: SessionsResponse = try await get("/api/session?limit=\(limit)&order=desc")
        return response.data
    }

    func sessions(projectID: String, limit: Int = 20) async throws -> [Session] {
        let encoded = projectID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? projectID
        let response: SessionsResponse = try await get("/api/session?project=\(encoded)&limit=\(limit)&order=desc")
        return response.data
    }

    /// Direct child sessions of a parent (subagents).
    func sessions(parentID: String, limit: Int = 50) async throws -> [Session] {
        let encoded = parentID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? parentID
        let response: SessionsResponse = try await get("/api/session?parentID=\(encoded)&limit=\(limit)&order=desc")
        return response.data
    }

    func session(id: String) async throws -> Session {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: SessionEnvelope = try await get("/api/session/\(encoded)")
        return response.data
    }

    /// Starts a new session in a project directory. The hub asks OpenCode to
    /// pick the default agent and model.
    func createSession(title: String?, directory: String) async throws -> Session {
        struct Location: Encodable { var directory: String }
        struct Body: Encodable {
            var title: String?
            var location: Location
        }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = Body(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            location: Location(directory: directory)
        )
        let data = try await send(
            "/api/session",
            method: "POST",
            body: try JSONEncoder().encode(body)
        )
        do {
            return try Self.decoder.decode(SessionEnvelope.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends a prompt into an existing session. If the session is running,
    /// `delivery` decides whether the message waits or steers the current turn.
    func promptSession(id: String, text: String, delivery: PromptDelivery? = nil) async throws {
        struct Body: Encodable {
            var text: String
            var delivery: PromptDelivery?
        }

        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let body = Body(text: text, delivery: delivery)
        _ = try await send(
            "/api/session/\(encoded)/prompt",
            method: "POST",
            body: try JSONEncoder().encode(body)
        )
    }

    /// Prompts admitted to the session but not delivered to the model yet,
    /// ordered oldest first.
    func sessionPending(id: String) async throws -> [SessionPending] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: SessionPendingResponse = try await get("/api/session/\(encoded)/pending")
        return response.data.filter(\.isUserPrompt)
    }

    /// Removes one queued prompt that the running turn has not consumed.
    func cancelPending(id: String, pendingID: String) async throws {
        let session = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let item = pendingID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pendingID
        _ = try await send("/api/session/\(session)/pending/\(item)", method: "DELETE")
    }

    func sessionMessages(
        id: String,
        limit: Int = 100,
        cursor: String? = nil,
        since: Double? = nil
    ) async throws -> SessionMessagesResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var path = "/api/session/\(encoded)/message?limit=\(limit)"
        if let cursor, let value = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            path += "&cursor=\(value)"
        }
        if let since, since.isFinite, since > 0 {
            path += "&since=\(Int(since))"
        }
        return try await get(path)
    }

    /// File patches written by a session's edit/write tool calls.
    func sessionChanges(id: String) async throws -> [FileChange] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: ChangesResponse = try await get("/api/session/\(encoded)/changes")
        return response.data
    }

    /// Per-session prompts, steps, tool reliability, failures and file totals.
    func sessionStats(id: String) async throws -> SessionStats {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: SessionStatsResponse = try await get("/api/session/\(encoded)/stats")
        return response.data
    }

    /// File patches across the newest sessions in a project.
    func projectChanges(id: String, sessions: Int = 10) async throws -> [FileChange] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: ChangesResponse = try await get(
            "/api/project/\(encoded)/changes?sessions=\(sessions)"
        )
        return response.data
    }

    /// Every file in the project folder, with git working-tree status when the
    /// project is a repository.
    func projectFiles(id: String) async throws -> ProjectFiles {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: ProjectFilesResponse = try await get("/api/project/\(encoded)/files")
        return response.data
    }

    /// The project's own app icon, discovered by the hub from the files in the
    /// project folder. nil when the folder has no usable artwork.
    func projectIcon(id: String) async -> Data? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return await iconData("/api/project/\(encoded)/icon")
    }

    func projects() async throws -> [Project] {
        try await get("/api/project")
    }

    func stats(project: String? = nil) async throws -> Stats {
        var path = "/api/experimental/session/stats"
        if let project {
            let encoded = project.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? project
            path += "?project=\(encoded)"
        }
        let response: StatsResponse = try await get(path)
        return response.data
    }

    func usage() async throws -> HubUsageResponse {
        try await get("/api/usage")
    }

    /// Fetches only the sessions and projects that changed after `since`.
    /// Passing `nil` asks for a full snapshot (first launch, or after a reset).
    func sync(since: Int?) async throws -> HubSyncResponse {
        if let since {
            return try await get("/api/sync?since=\(since)")
        }
        return try await get("/api/sync")
    }

    /// Asks the hub to pull fresh data from OpenCode. Best effort — failures are
    /// reported by the normal refresh path.
    func sync() async throws {
        _ = try await send("/api/sync", method: "POST")
    }
}

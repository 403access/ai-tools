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

    /// Changes coalescing and sleep settings sent to the apps. The hub applies
    /// them immediately and persists them for the next launch. Omitted values
    /// are left unchanged.
    func updateSettings(
        eventThrottleMs: Int? = nil,
        preventSleep: Bool? = nil
    ) async throws -> ServerSettings {
        struct Body: Encodable {
            var eventThrottleMs: Int?
            var preventSleep: Bool?
        }
        let body = try JSONEncoder().encode(
            Body(eventThrottleMs: eventThrottleMs, preventSleep: preventSleep)
        )
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

    /// Sends a playback or output-volume action to the hub host. The response
    /// carries the updated media and audio state.
    func controlMedia(action: String, value: Double? = nil) async throws -> MediaControlResult {
        struct Body: Encodable {
            var action: String
            var value: Double?
        }
        let body = try JSONEncoder().encode(Body(action: action, value: value))
        let data = try await send("/api/media", method: "POST", body: body)
        do {
            return try Self.decoder.decode(MediaControlEnvelope.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - Terminals

    /// Every PTY the hub can see, including terminals started in OpenCode's
    /// own TUI. Each carries the location it belongs to.
    func terminals(force: Bool = false) async throws -> [SystemTerminal] {
        let response: TerminalsEnvelope = try await get(
            force ? "/api/terminals?refresh=1" : "/api/terminals"
        )
        return response.data
    }

    /// Starts an interactive shell in `directory` (the OpenCode location).
    func createTerminal(
        title: String?,
        cwd: String?,
        location: String
    ) async throws -> SystemTerminal {
        let request = TerminalCreateRequest(
            title: title,
            cwd: cwd,
            command: nil,
            location: location
        )
        let data = try JSONEncoder().encode(request)
        let response = try await send("/api/terminals", method: "POST", body: data)
        do {
            return try Self.decoder.decode(TerminalEnvelope.self, from: response).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Resizes (and optionally renames) a terminal. OpenCode resizes normal
    /// PTYs over HTTP rather than through the socket.
    func updateTerminal(
        id: String,
        title: String? = nil,
        size: TerminalSize? = nil,
        location: String
    ) async throws -> SystemTerminal {
        let request = TerminalUpdateRequest(title: title, size: size, location: location)
        let data = try JSONEncoder().encode(request)
        let response = try await send(
            Self.terminalPath(id, location: nil),
            method: "PUT",
            body: data
        )
        do {
            return try Self.decoder.decode(TerminalEnvelope.self, from: response).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Stops and removes a terminal process.
    func removeTerminal(id: String, location: String) async throws {
        _ = try await send(
            Self.terminalPath(id, location: location),
            method: "DELETE"
        )
    }

    /// WebSocket request for a terminal's live output and input. The hub
    /// proxies the PTY so the client never needs OpenCode's credentials.
    func terminalSocketRequest(
        id: String,
        location: String,
        cursor: Int? = nil
    ) throws -> URLRequest {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard var components = URLComponents(
            url: try url(for: "/api/terminals/\(encoded)/socket").absoluteURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.badURL
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        var items = [URLQueryItem(name: "location", value: location)]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: String(cursor)))
        }
        components.queryItems = items
        guard let socketURL = components.url else { throw APIError.badURL }

        var request = URLRequest(url: socketURL)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (header, value) in DeviceIdentity.headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    // MARK: - Remote desktop

    /// Status of the hub's screen-capture helper, including display geometry
    /// and whether macOS has granted Screen Recording and Accessibility.
    func remoteStatus() async throws -> RemoteDesktopStatus {
        let response: RemoteStatusEnvelope = try await get("/api/remote")
        return response.data
    }

    /// Asks the helper to prompt macOS for one or both privacy permissions.
    /// The prompt appears on the Mac, not on the phone.
    func requestRemotePermissions(
        screenRecording: Bool,
        accessibility: Bool
    ) async throws -> RemoteDesktopStatus {
        struct Body: Encodable {
            var screenRecording: Bool
            var accessibility: Bool
        }
        let body = try JSONEncoder().encode(
            Body(screenRecording: screenRecording, accessibility: accessibility)
        )
        let data = try await send("/api/remote/permissions", method: "POST", body: body)
        do {
            return try Self.decoder.decode(RemoteStatusEnvelope.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Changes capture resolution or frame rate. The hub applies the values to
    /// the helper and returns the new status.
    func configureRemote(
        fps: Int? = nil,
        quality: Double? = nil,
        maxWidth: Int? = nil,
        displayID: UInt32? = nil
    ) async throws -> RemoteDesktopStatus {
        struct Body: Encodable {
            var fps: Int?
            var quality: Double?
            var maxWidth: Int?
            var displayID: UInt32?
        }
        let body = try JSONEncoder().encode(
            Body(fps: fps, quality: quality, maxWidth: maxWidth, displayID: displayID)
        )
        let data = try await send("/api/remote/configure", method: "POST", body: body)
        do {
            return try Self.decoder.decode(RemoteStatusEnvelope.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// WebSocket that streams JPEG frames and accepts pointer, scroll, and key
    /// messages. The hub fans one capture out to every connected viewer.
    func remoteSocketRequest() throws -> URLRequest {
        guard var components = URLComponents(
            url: try url(for: "/api/remote/socket").absoluteURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.badURL
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let socketURL = components.url else { throw APIError.badURL }

        var request = URLRequest(url: socketURL)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (header, value) in DeviceIdentity.headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    private static func terminalPath(_ id: String, location: String?) -> String {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var components = URLComponents()
        components.path = "/api/terminals/\(encoded)"
        if let location {
            components.queryItems = [URLQueryItem(name: "location", value: location)]
        }
        return components.string ?? "/api/terminals/\(encoded)"
    }

    // MARK: - Terminal.app tabs

    /// Tabs open in Terminal.app on the hub host. Empty on other platforms.
    func hostTerminals(force: Bool = false) async throws -> [HostTerminal] {
        let response: HostTerminalsEnvelope = try await get(
            force ? "/api/host-terminals?refresh=1" : "/api/host-terminals"
        )
        return response.data
    }

    /// Plain-text mirror of one tab, optionally with its full scrollback.
    func hostTerminal(id: String, history: Bool = false) async throws -> HostTerminalDetail {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var path = "/api/host-terminals/\(encoded)"
        if history { path += "?history=1" }
        let response: HostTerminalEnvelope = try await get(path)
        return response.data
    }

    /// Runs one line in an existing Terminal.app tab.
    func sendHostTerminalCommand(id: String, command: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let body = try JSONEncoder().encode(HostTerminalCommandRequest(command: command))
        _ = try await send(
            "/api/host-terminals/\(encoded)/command",
            method: "POST",
            body: body
        )
    }

    /// Brings the tab to the front on the Mac.
    func focusHostTerminal(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await send(
            "/api/host-terminals/\(encoded)/focus",
            method: "POST"
        )
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

/**
 * OpenAPI path definitions for the hub API.
 *
 * Keep these in sync with the routing chain in `api.ts`. The test suite walks
 * every `$ref` and every path parameter so typos fail the build.
 */

type Schema = Record<string, unknown>;

const schemaRef = (name: string): Schema => ({ $ref: `#/components/schemas/${name}` });

const jsonResponse = (description: string, schema?: Schema): Schema => ({
  description,
  ...(schema
    ? { content: { "application/json": { schema } } }
    : {}),
});

const ok = (schema: Schema): Schema => jsonResponse("Successful response", schema);
const unauthorized: Schema = { $ref: "#/components/responses/Unauthorized" };
const badRequest: Schema = { $ref: "#/components/responses/BadRequest" };
const notFound: Schema = { $ref: "#/components/responses/NotFound" };
const unavailable: Schema = { $ref: "#/components/responses/ServiceUnavailable" };
const failure: Schema = { $ref: "#/components/responses/Error" };

const pathParam = (name: string, description: string, schema: Schema = { type: "string" }): Schema => ({
  name,
  in: "path",
  required: true,
  description,
  schema,
});

const queryParam = (name: string, description: string, schema: Schema = { type: "string" }): Schema => ({
  name,
  in: "query",
  required: false,
  description,
  schema,
});

const refreshParam = queryParam("refresh", "Bypass the short-lived list/snapshot cache.", {
  type: "string",
  enum: ["1"],
});

const jsonBody = (schema: Schema, required = true): Schema => ({
  required,
  content: { "application/json": { schema } },
});

const noContent: Schema = { description: "No content" };

/** Device headers every authenticated client may send. */
export const DEVICE_HEADER_PARAMETERS: Schema[] = [
  {
    name: "X-OpenCodeBar-Device-Id",
    in: "header",
    required: false,
    description: "Stable device identifier. A request without it is not added to the device list.",
    schema: { type: "string" },
  },
  {
    name: "X-OpenCodeBar-Device-Name",
    in: "header",
    required: false,
    description: "Human-readable device name shown in Settings.",
    schema: { type: "string" },
  },
  {
    name: "X-OpenCodeBar-Platform",
    in: "header",
    required: false,
    description: "Platform name, for example `macOS` or `iOS`.",
    schema: { type: "string" },
  },
  {
    name: "X-OpenCodeBar-App-Version",
    in: "header",
    required: false,
    description: "Client app version.",
    schema: { type: "string" },
  },
];

/** Paths that stay available without a token and do not take device headers. */
export const PUBLIC_PATHS = ["/api/ping", "/api/docs", "/api/openapi.json"];

export const PATHS = {
  "/api/ping": {
    get: {
      tags: ["Health"],
      summary: "Unauthenticated liveness probe",
      description:
        "Used by clients to confirm that a pasted URL points at an OpenCodeBar hub before sending the token.",
      operationId: "pingHub",
      security: [],
      responses: {
        200: ok(schemaRef("PingResponse")),
      },
    },
  },

  "/api/docs": {
    get: {
      tags: ["Documentation"],
      summary: "Swagger UI",
      description:
        "Interactive API explorer. Loads `/api/openapi.json` and lets you authorize with the hub token.",
      operationId: "apiDocs",
      security: [],
      responses: {
        200: {
          description: "Swagger UI HTML page",
          content: { "text/html": { schema: { type: "string" } } },
        },
      },
    },
  },

  "/api/openapi.json": {
    get: {
      tags: ["Documentation"],
      summary: "OpenAPI document",
      description: "Machine-readable OpenAPI 3.0 description of this API.",
      operationId: "openApiDocument",
      security: [],
      responses: {
        200: {
          description: "OpenAPI document",
          content: {
            "application/json": {
              schema: { type: "object", additionalProperties: true },
            },
          },
        },
      },
    },
  },

  "/api/health": {
    get: {
      tags: ["Health"],
      summary: "Hub and OpenCode health",
      operationId: "getHealth",
      responses: {
        200: ok(schemaRef("HealthResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/hub/info": {
    get: {
      tags: ["Health"],
      summary: "Alias for hub health",
      operationId: "getHubInfo",
      responses: {
        200: ok(schemaRef("HealthResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/info": {
    get: {
      tags: ["Health"],
      summary: "Server info, URLs, and capabilities",
      operationId: "getServerInfo",
      responses: {
        200: ok(schemaRef("ServerInfo")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/session": {
    get: {
      tags: ["Sessions"],
      summary: "List cached sessions",
      operationId: "listSessions",
      parameters: [
        queryParam("limit", "Maximum sessions to return (1–5000). Defaults to 60.", {
          type: "integer", minimum: 1, maximum: 5000, default: 60,
        }),
        queryParam("offset", "Rows to skip (0–1,000,000). Defaults to 0.", {
          type: "integer", minimum: 0, maximum: 1_000_000, default: 0,
        }),
        queryParam("project", "Filter by project id."),
        queryParam("parentID", "Filter by parent session id."),
        queryParam("active", "Only return running sessions.", {
          type: "string", enum: ["true"],
        }),
        queryParam("order", "Sort by update time. Defaults to `desc`.", {
          type: "string", enum: ["asc", "desc"], default: "desc",
        }),
        queryParam("q", "Search titles and directories."),
      ],
      responses: {
        200: ok(schemaRef("SessionsResponse")),
        401: unauthorized,
        default: failure,
      },
    },
    post: {
      tags: ["Sessions"],
      summary: "Create a session",
      description: "Forwarded to OpenCode. `location.directory` is required.",
      operationId: "createSession",
      requestBody: jsonBody(schemaRef("CreateSessionRequest")),
      responses: {
        200: ok(schemaRef("SessionResponse")),
        400: badRequest,
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/session/active": {
    get: {
      tags: ["Sessions"],
      summary: "Active session map",
      operationId: "getActiveSessions",
      responses: {
        200: ok(schemaRef("ActiveSessionsResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/task": {
    get: {
      tags: ["Tasks"],
      summary: "List board tasks",
      description:
        "Top-level sessions the hub tracks as tasks, newest first. Each carries a derived `task.status` and automatic labels.",
      operationId: "listTasks",
      parameters: [
        queryParam("limit", "Maximum tasks to return (1–5000). Defaults to 500.", {
          type: "integer", minimum: 1, maximum: 5000, default: 500,
        }),
        queryParam("project", "Filter by project id."),
      ],
      responses: {
        200: ok(schemaRef("SessionsResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/task/{id}": {
    patch: {
      tags: ["Tasks"],
      summary: "Resolve a task",
      description:
        "Marks a task done, reopens it, or dismisses it. Sending another prompt into the session also reopens it.",
      operationId: "updateTask",
      parameters: [pathParam("id", "Session id of the task.")],
      requestBody: jsonBody(schemaRef("TaskStatusUpdateRequest")),
      responses: {
        200: ok(schemaRef("SessionResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/model": {
    get: {
      tags: ["Sessions"],
      summary: "Models available for a directory",
      description: "Forwarded from OpenCode so clients can offer a model picker.",
      operationId: "listModels",
      parameters: [queryParam("directory", "Directory whose provider config should be used.")],
      responses: {
        200: ok(schemaRef("ModelsResponse")),
        401: unauthorized,
        503: unavailable,
        default: failure,
      },
    },
  },

  "/api/model/default": {
    get: {
      tags: ["Sessions"],
      summary: "Default model for a directory",
      description: "Used when a session has no explicit model selection.",
      operationId: "getDefaultModel",
      parameters: [queryParam("directory", "Directory whose provider config should be used.")],
      responses: {
        200: ok(schemaRef("ModelResponse")),
        401: unauthorized,
        503: unavailable,
        default: failure,
      },
    },
  },

  "/api/agent": {
    get: {
      tags: ["Sessions"],
      summary: "Agents registered for a directory",
      description: "Forwarded from OpenCode so clients can offer an agent picker.",
      operationId: "listAgents",
      parameters: [queryParam("directory", "Directory whose agent config should be used.")],
      responses: {
        200: ok(schemaRef("AgentsResponse")),
        401: unauthorized,
        503: unavailable,
        default: failure,
      },
    },
  },

  "/api/session/{id}": {
    get: {
      tags: ["Sessions"],
      summary: "One session",
      operationId: "getSession",
      parameters: [pathParam("id", "Session id.")],
      responses: {
        200: ok(schemaRef("SessionResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/session/{id}/message": {
    get: {
      tags: ["Sessions"],
      summary: "Paged session messages",
      description:
        "Pass `since` (milliseconds) for a delta with no cursor, or `cursor` from the previous page.",
      operationId: "listSessionMessages",
      parameters: [
        pathParam("id", "Session id."),
        queryParam("limit", "Maximum messages (1–500). Defaults to 100.", {
          type: "integer", minimum: 1, maximum: 500, default: 100,
        }),
        queryParam("cursor", "Cursor from the previous response."),
        queryParam("since", "Only messages created or updated at/after this time.", {
          type: "number",
        }),
      ],
      responses: {
        200: ok(schemaRef("MessagesResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/session/{id}/fork": {
    post: {
      tags: ["Sessions"],
      summary: "Fork a session",
      description:
        "Copies projected history into a new child session. `before` excludes that message and everything after it.",
      operationId: "forkSession",
      parameters: [pathParam("id", "Session id.")],
      requestBody: jsonBody(
        {
          type: "object",
          properties: {
            before: { type: "string", nullable: true, description: "Message id to fork before." },
          },
        },
        false,
      ),
      responses: {
        200: ok(schemaRef("SessionResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/session/{id}/model": {
    post: {
      tags: ["Sessions"],
      summary: "Switch the session model",
      description: "Applies to subsequent turns. Forwarded to OpenCode.",
      operationId: "switchSessionModel",
      parameters: [pathParam("id", "Session id.")],
      requestBody: jsonBody({
        type: "object",
        required: ["model"],
        properties: { model: { $ref: "#/components/schemas/ModelRef" } },
      }),
      responses: {
        204: noContent,
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/session/{id}/agent": {
    post: {
      tags: ["Sessions"],
      summary: "Switch the session agent",
      description: "Applies to subsequent turns. Forwarded to OpenCode.",
      operationId: "switchSessionAgent",
      parameters: [pathParam("id", "Session id.")],
      requestBody: jsonBody({
        type: "object",
        required: ["agent"],
        properties: { agent: { type: "string" } },
      }),
      responses: {
        204: noContent,
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/session/{id}/children": {
    get: {
      tags: ["Sessions"],
      summary: "Child sessions",
      operationId: "listSessionChildren",
      parameters: [pathParam("id", "Parent session id.")],
      responses: {
        200: ok(schemaRef("SessionChildrenResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/session/{id}/forks": {
    get: {
      tags: ["Sessions"],
      summary: "Forked sessions",
      description:
        "Sessions forked from this conversation, newest first. Each fork carries `fork.sessionID` pointing back to this session.",
      operationId: "listSessionForks",
      parameters: [pathParam("id", "Source session id.")],
      responses: {
        200: ok(schemaRef("SessionForksResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/session/{id}/changes": {
    get: {
      tags: ["Sessions"],
      summary: "File patches produced by a session",
      operationId: "getSessionChanges",
      parameters: [pathParam("id", "Session id.")],
      responses: {
        200: ok(schemaRef("ChangesResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/session/{id}/git": {
    get: {
      tags: ["Sessions"],
      summary: "Commit information for a session",
      description:
        "Reads the session's work tree and lists commits authored while the session was active, plus the current branch and HEAD.",
      operationId: "getSessionGit",
      parameters: [
        pathParam("id", "Session id."),
        queryParam("limit", "Maximum commits (1–20000). Defaults to 2000.", {
          type: "integer", minimum: 1, maximum: 20_000, default: 2_000,
        }),
      ],
      responses: {
        200: ok(schemaRef("SessionGitResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/session/{id}/stats": {
    get: {
      tags: ["Sessions"],
      summary: "Derived session statistics",
      operationId: "getSessionStats",
      parameters: [pathParam("id", "Session id.")],
      responses: {
        200: ok(schemaRef("SessionStatsResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/session/{id}/pending": {
    get: {
      tags: ["Sessions"],
      summary: "Prompts admitted but not delivered",
      description: "Oldest first. The queue lives in OpenCode and is empty when the service is offline.",
      operationId: "listPendingInputs",
      parameters: [pathParam("id", "Session id.")],
      responses: {
        200: ok(schemaRef("PendingInputsResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/session/{id}/pending/{inputID}": {
    delete: {
      tags: ["Sessions"],
      summary: "Withdraw a queued prompt",
      description: "A no-op once the running turn has read the prompt.",
      operationId: "cancelPendingInput",
      parameters: [
        pathParam("id", "Session id."),
        pathParam("inputID", "Pending input id."),
      ],
      responses: {
        204: noContent,
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/session/{id}/prompt": {
    post: {
      tags: ["Sessions"],
      summary: "Send a prompt",
      operationId: "promptSession",
      parameters: [pathParam("id", "Session id.")],
      requestBody: jsonBody(schemaRef("PromptRequest")),
      responses: {
        200: ok({ type: "object", additionalProperties: true }),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/session/{id}/pause": {
    post: {
      tags: ["Sessions"],
      summary: "Pause a session until a time",
      description:
        "Interrupts the active turn and holds the session until the given time. The hub sends `continue` when the deadline passes, even after a restart.",
      operationId: "pauseSession",
      parameters: [pathParam("id", "Session id.")],
      requestBody: jsonBody(schemaRef("PauseSessionRequest")),
      responses: {
        200: ok(schemaRef("SessionResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        503: unavailable,
        default: failure,
      },
    },
  },

  "/api/session/{id}/stop": {
    post: {
      tags: ["Sessions"],
      summary: "Stop a session",
      description:
        "Interrupts the active turn and holds the session until the user continues it. A stop has no automatic deadline.",
      operationId: "stopSession",
      parameters: [pathParam("id", "Session id.")],
      responses: {
        200: ok(schemaRef("SessionResponse")),
        401: unauthorized,
        404: notFound,
        503: unavailable,
        default: failure,
      },
    },
  },

  "/api/session/{id}/continue": {
    post: {
      tags: ["Sessions"],
      summary: "Continue a paused or stopped session",
      description:
        "Clears the pause or stop and sends `continue` into the conversation to restart the agent loop.",
      operationId: "continueSession",
      parameters: [pathParam("id", "Session id.")],
      responses: {
        200: ok(schemaRef("SessionResponse")),
        401: unauthorized,
        404: notFound,
        503: unavailable,
        default: failure,
      },
    },
  },

  "/api/experimental/session/stats": {
    get: {
      tags: ["Sessions", "Usage"],
      summary: "Global statistics",
      operationId: "getGlobalStats",
      parameters: [queryParam("project", "Limit stats to one project id.")],
      responses: {
        200: ok(schemaRef("StatsResponse")),
        401: unauthorized,
        503: unavailable,
        default: failure,
      },
    },
  },

  "/api/search": {
    get: {
      tags: ["Sessions"],
      summary: "Search sessions",
      operationId: "searchSessions",
      parameters: [
        queryParam("q", "Search text. Defaults to an empty string.", { type: "string", default: "" }),
        queryParam("limit", "Maximum results (1–500). Defaults to 50.", {
          type: "integer", minimum: 1, maximum: 500, default: 50,
        }),
      ],
      responses: {
        200: ok(schemaRef("SessionsResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/git/clone": {
    post: {
      tags: ["Projects"],
      summary: "Clone a git repository",
      description:
        "Runs `git clone` on the hub host and returns the new project directory. The destination must not exist yet; use the returned path to start a session.",
      operationId: "cloneRepository",
      requestBody: jsonBody(schemaRef("CloneRepositoryRequest")),
      responses: {
        200: ok(schemaRef("CloneRepositoryResponse")),
        400: badRequest,
        401: unauthorized,
        409: { description: "The destination folder already exists." },
        422: { description: "git could not clone the repository." },
        504: { description: "The clone exceeded the hub's time limit." },
        default: failure,
      },
    },
  },

  "/api/project": {
    get: {
      tags: ["Projects"],
      summary: "All projects",
      description: "Returns OpenCode's plain array shape.",
      operationId: "listProjects",
      responses: {
        200: ok(schemaRef("ProjectsResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/project/{id}": {
    get: {
      tags: ["Projects"],
      summary: "One project",
      operationId: "getProject",
      parameters: [pathParam("id", "Project id.")],
      responses: {
        200: ok(schemaRef("ProjectResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/project/{id}/changes": {
    get: {
      tags: ["Projects"],
      summary: "Aggregated project changes",
      operationId: "getProjectChanges",
      parameters: [
        pathParam("id", "Project id."),
        queryParam("sessions", "How many newer sessions to hydrate (1–100). Defaults to 10.", {
          type: "integer", minimum: 1, maximum: 100, default: 10,
        }),
      ],
      responses: {
        200: ok(schemaRef("ChangesResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/project/{id}/files": {
    get: {
      tags: ["Projects"],
      summary: "Project files with git status",
      operationId: "listProjectFiles",
      parameters: [pathParam("id", "Project id.")],
      responses: {
        200: ok(schemaRef("ProjectFilesResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/project/{id}/git": {
    get: {
      tags: ["Projects"],
      summary: "Project repository graph",
      description:
        "Returns every reachable commit across all refs, plus branches, tags, and the current working-tree state. `data` is null when the folder is not a git work tree.",
      operationId: "getProjectGit",
      parameters: [
        pathParam("id", "Project id."),
        queryParam("limit", "Maximum commits (1–20000). Defaults to 2000.", {
          type: "integer", minimum: 1, maximum: 20_000, default: 2_000,
        }),
      ],
      responses: {
        200: ok(schemaRef("GitRepositoryResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/project/{id}/icon": {
    get: {
      tags: ["Projects"],
      summary: "Project app icon",
      description: "Returns image bytes with an `ETag`; `304` when `If-None-Match` matches.",
      operationId: "getProjectIcon",
      parameters: [pathParam("id", "Project id.")],
      responses: {
        200: {
          description: "Icon artwork",
          content: {
            "image/png": { schema: { type: "string", format: "binary" } },
            "image/jpeg": { schema: { type: "string", format: "binary" } },
            "image/webp": { schema: { type: "string", format: "binary" } },
          },
        },
        304: { description: "Not modified" },
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/sync": {
    get: {
      tags: ["Events & sync"],
      summary: "Incremental session/project feed",
      description:
        "Without `since` returns a full snapshot. `full: true` means the client must replace its local copy.",
      operationId: "getSync",
      parameters: [
        queryParam("since", "Revision from the previous response.", {
          type: "integer", minimum: 0,
        }),
      ],
      responses: {
        200: ok(schemaRef("SyncResponse")),
        401: unauthorized,
        default: failure,
      },
    },
    post: {
      tags: ["Events & sync"],
      summary: "Force a sync",
      operationId: "forceSync",
      responses: {
        200: ok(schemaRef("OkResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/event": {
    get: {
      tags: ["Events & sync"],
      summary: "Live Server-Sent Events stream",
      description:
        "Sends `retry: 2000`, one `data:` JSON HubEvent per update, and a `: ping` comment every 15 seconds. " +
        "Missed events are not replayed; catch up with `/api/sync`.",
      operationId: "streamEvents",
      parameters: [
        queryParam("token", "Hub token, for SSE clients that cannot set an Authorization header."),
      ],
      responses: {
        200: {
          description: "Event stream",
          content: { "text/event-stream": { schema: schemaRef("EventStream") } },
        },
        401: unauthorized,
      },
    },
  },

  "/api/usage": {
    get: {
      tags: ["Usage"],
      summary: "Go plan usage windows",
      operationId: "getUsage",
      responses: {
        200: ok(schemaRef("UsageResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/devices": {
    get: {
      tags: ["Devices"],
      summary: "Connected devices",
      operationId: "listDevices",
      responses: {
        200: ok(schemaRef("DevicesResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/settings": {
    get: {
      tags: ["Settings"],
      summary: "Hub settings",
      operationId: "getSettings",
      responses: {
        200: ok(schemaRef("HubSettingsResponse")),
        401: unauthorized,
        default: failure,
      },
    },
    patch: {
      tags: ["Settings"],
      summary: "Update hub settings",
      description:
        "Changes apply immediately and are persisted for the next launch. Out-of-range throttle values are clamped.",
      operationId: "updateSettings",
      requestBody: jsonBody(schemaRef("SettingsPatch")),
      responses: {
        200: ok(schemaRef("HubSettingsResponse")),
        400: badRequest,
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/server/restart": {
    post: {
      tags: ["Settings"],
      summary: "Restart the hub process",
      operationId: "restartHub",
      responses: {
        200: ok(schemaRef("OkResponse")),
        401: unauthorized,
        501: unavailable,
        default: failure,
      },
    },
  },

  "/api/terminals": {
    get: {
      tags: ["Terminals"],
      summary: "List PTYs across OpenCode locations",
      operationId: "listTerminals",
      parameters: [refreshParam],
      responses: {
        200: ok(schemaRef("TerminalsResponse")),
        401: unauthorized,
        default: failure,
      },
    },
    post: {
      tags: ["Terminals"],
      summary: "Start a PTY",
      operationId: "createTerminal",
      requestBody: jsonBody(schemaRef("TerminalCreateRequest"), false),
      responses: {
        200: ok(schemaRef("TerminalResponse")),
        400: badRequest,
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/terminals/{id}": {
    get: {
      tags: ["Terminals"],
      summary: "One terminal",
      operationId: "getTerminal",
      parameters: [pathParam("id", "Terminal id.")],
      responses: {
        200: ok(schemaRef("TerminalResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
    put: {
      tags: ["Terminals"],
      summary: "Rename or resize a terminal",
      operationId: "updateTerminal",
      parameters: [
        pathParam("id", "Terminal id."),
        queryParam("location", "OpenCode location that owns the PTY, when not in the body."),
      ],
      requestBody: jsonBody(schemaRef("TerminalUpdateRequest"), false),
      responses: {
        200: ok(schemaRef("TerminalResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
    delete: {
      tags: ["Terminals"],
      summary: "Stop and remove a terminal",
      operationId: "deleteTerminal",
      parameters: [
        pathParam("id", "Terminal id."),
        queryParam("location", "OpenCode location that owns the PTY."),
      ],
      responses: {
        200: ok(schemaRef("OkResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/terminals/{id}/socket": {
    get: {
      tags: ["Terminals"],
      summary: "Terminal WebSocket",
      description:
        "Text frames are raw terminal I/O. A binary frame starting with `0x00` carries `{\"cursor\": n}` " +
        "and marks the end of the replay. Send `\\r` for Enter.",
      operationId: "terminalSocket",
      parameters: [
        pathParam("id", "Terminal id."),
        queryParam("location", "OpenCode location that owns the PTY."),
        queryParam("cursor", "Last output position, for resuming after a reconnect."),
      ],
      responses: {
        101: { description: "Switching Protocols; terminal stream attached" },
        401: unauthorized,
        501: unavailable,
      },
    },
  },

  "/api/host-terminals": {
    get: {
      tags: ["Host terminals"],
      summary: "Tabs open in Terminal.app",
      operationId: "listHostTerminals",
      parameters: [refreshParam],
      responses: {
        200: ok(schemaRef("HostTerminalsResponse")),
        401: unauthorized,
        501: unavailable,
        default: failure,
      },
    },
  },

  "/api/host-terminals/{tty}": {
    get: {
      tags: ["Host terminals"],
      summary: "Terminal.app tab text mirror",
      operationId: "getHostTerminal",
      parameters: [
        pathParam("tty", "TTY device name without `/dev/`, for example `ttys001`."),
        queryParam("history", "Include full scrollback.", { type: "string", enum: ["1"] }),
      ],
      responses: {
        200: ok(schemaRef("HostTerminalResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/host-terminals/{tty}/command": {
    post: {
      tags: ["Host terminals"],
      summary: "Run a line in a Terminal.app tab",
      description: "Behaves like typing the line and pressing Return. Empty command presses Return.",
      operationId: "runHostTerminalCommand",
      parameters: [pathParam("tty", "TTY device name without `/dev/`.")],
      requestBody: jsonBody(schemaRef("HostTerminalCommandRequest")),
      responses: {
        200: ok(schemaRef("OkResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        503: unavailable,
        default: failure,
      },
    },
  },

  "/api/host-terminals/{tty}/focus": {
    post: {
      tags: ["Host terminals"],
      summary: "Focus a Terminal.app tab",
      operationId: "focusHostTerminal",
      parameters: [pathParam("tty", "TTY device name without `/dev/`.")],
      responses: {
        200: ok(schemaRef("OkResponse")),
        401: unauthorized,
        404: notFound,
        503: unavailable,
        default: failure,
      },
    },
  },

  "/api/files": {
    get: {
      tags: ["Host files"],
      summary: "List one folder",
      description: "Paths must be absolute or start with `~`. Defaults to the home directory.",
      operationId: "listHostDirectory",
      parameters: [queryParam("path", "Folder to list.")],
      responses: {
        200: ok(schemaRef("HostDirectoryResponse")),
        401: unauthorized,
        403: { $ref: "#/components/responses/Forbidden" },
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/files/content": {
    get: {
      tags: ["Host files"],
      summary: "Read a file's metadata and text",
      description: "Text is capped at 512 KB; images are fetched through `/api/files/raw`.",
      operationId: "readHostFile",
      parameters: [queryParam("path", "File to read.")],
      responses: {
        200: ok(schemaRef("HostFileContentResponse")),
        401: unauthorized,
        403: { $ref: "#/components/responses/Forbidden" },
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/files/raw": {
    get: {
      tags: ["Host files"],
      summary: "Raw file bytes",
      description: "Capped at 25 MB. Hub and OpenCode credential files are blocked.",
      operationId: "readHostFileRaw",
      parameters: [queryParam("path", "File to read.")],
      responses: {
        200: {
          description: "File bytes",
          content: { "application/octet-stream": { schema: { type: "string", format: "binary" } } },
        },
        401: unauthorized,
        403: { $ref: "#/components/responses/Forbidden" },
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/system": {
    get: {
      tags: ["System"],
      summary: "Host system snapshot",
      description:
        "Dynamic sections refresh every request; expensive inventory is cached for five minutes. " +
        "`refresh=1` bypasses both caches.",
      operationId: "getSystemSnapshot",
      parameters: [refreshParam],
      responses: {
        200: ok(schemaRef("SystemInfoResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/system/apps/icon": {
    get: {
      tags: ["System"],
      summary: "Installed app icon",
      description: "Only apps in the current snapshot are accepted. Returns `404` when artwork is unavailable.",
      operationId: "getSystemAppIcon",
      parameters: [queryParam("path", "Application path from the snapshot.")],
      responses: {
        200: {
          description: "Icon artwork",
          content: {
            "image/png": { schema: { type: "string", format: "binary" } },
            "image/jpeg": { schema: { type: "string", format: "binary" } },
          },
        },
        304: { description: "Not modified" },
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/system/apps/detail": {
    get: {
      tags: ["System"],
      summary: "App bundle facts and provider inventory",
      operationId: "getSystemAppDetail",
      parameters: [queryParam("path", "Application path from the snapshot.")],
      responses: {
        200: ok(schemaRef("SystemAppDetailResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        501: unavailable,
        default: failure,
      },
    },
  },

  "/api/system/apps/action": {
    post: {
      tags: ["System"],
      summary: "Manage an app's resources",
      description:
        "Currently supports Xcode simulator and runtime actions. Targets must exist in the current inventory.",
      operationId: "runSystemAppAction",
      requestBody: jsonBody(schemaRef("SystemAppActionRequest")),
      responses: {
        200: ok(schemaRef("SystemAppDetailResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        501: unavailable,
        default: failure,
      },
    },
  },

  "/api/media": {
    post: {
      tags: ["System"],
      summary: "Playback or volume command",
      operationId: "controlMedia",
      requestBody: jsonBody(schemaRef("MediaRequest")),
      responses: {
        200: ok(schemaRef("MediaControlResponse")),
        400: badRequest,
        401: unauthorized,
        409: {
          description: "Nothing is playing for playback commands.",
          content: {
            "application/json": { schema: schemaRef("ErrorResponse") },
          },
        },
        501: unavailable,
        default: failure,
      },
    },
  },

  "/api/remote": {
    get: {
      tags: ["Remote desktop"],
      summary: "Capture helper status",
      operationId: "getRemoteStatus",
      responses: {
        200: ok(schemaRef("RemoteStatusResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/remote/configure": {
    post: {
      tags: ["Remote desktop"],
      summary: "Change capture settings",
      operationId: "configureRemote",
      requestBody: jsonBody(schemaRef("RemoteConfigureRequest")),
      responses: {
        200: ok(schemaRef("RemoteStatusResponse")),
        400: badRequest,
        401: unauthorized,
        501: unavailable,
        default: failure,
      },
    },
  },

  "/api/remote/permissions": {
    post: {
      tags: ["Remote desktop"],
      summary: "Request Screen Recording / Accessibility",
      operationId: "requestRemotePermissions",
      requestBody: jsonBody(schemaRef("RemotePermissionsRequest"), false),
      responses: {
        200: ok(schemaRef("RemoteStatusResponse")),
        400: badRequest,
        401: unauthorized,
        501: unavailable,
        default: failure,
      },
    },
  },

  "/api/remote/socket": {
    get: {
      tags: ["Remote desktop"],
      summary: "Remote desktop WebSocket",
      description:
        "Server sends JSON status/log text messages and binary JPEG frames (15-byte header starting `0x02RD`). " +
        "Client messages are JSON `pointer`, `scroll`, `key`, `text`, `configure`, `permissions`, and `status`.",
      operationId: "remoteSocket",
      responses: {
        101: { description: "Switching Protocols; remote-desktop stream attached" },
        401: unauthorized,
        501: unavailable,
      },
    },
  },

  "/api/vms": {
    get: {
      tags: ["Virtual machines"],
      summary: "Virtual-machine definitions and status",
      operationId: "listVMs",
      responses: {
        200: ok(schemaRef("VirtualMachinesResponse")),
        401: unauthorized,
        default: failure,
      },
    },
    post: {
      tags: ["Virtual machines"],
      summary: "Create a NixOS VM",
      description: "The build runs asynchronously; poll the VM or its build log.",
      operationId: "createVM",
      requestBody: jsonBody(schemaRef("VMCreateRequest")),
      responses: {
        201: {
          description: "Created; the build runs asynchronously.",
          content: { "application/json": { schema: schemaRef("VirtualMachineResponse") } },
        },
        400: badRequest,
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/vms/capabilities": {
    get: {
      tags: ["Virtual machines"],
      summary: "Host support and setup readiness",
      operationId: "getVMCapabilities",
      responses: {
        200: ok(schemaRef("VMCapabilitiesResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/vms/catalog": {
    get: {
      tags: ["Virtual machines"],
      summary: "NixOS configuration catalog",
      description:
        "Categories, clickable options, presets, defaults, and limits used by the configuration builder in both apps.",
      operationId: "getVMConfigCatalog",
      responses: {
        200: ok(schemaRef("VMConfigCatalogResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/vms/preview": {
    post: {
      tags: ["Virtual machines"],
      summary: "Render and summarize a draft configuration",
      description:
        "Returns the generated `configuration.nix`, package/service/port plan, dependency additions, and warnings without creating a VM.",
      operationId: "previewVMConfig",
      requestBody: jsonBody(schemaRef("VMConfigPreviewRequest"), false),
      responses: {
        200: ok(schemaRef("VMConfigPreviewResponse")),
        400: badRequest,
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/vms/setup": {
    get: {
      tags: ["Virtual machines"],
      summary: "Current or last setup job",
      operationId: "getVMSetup",
      responses: {
        200: ok(schemaRef("VMSetupJobResponse")),
        401: unauthorized,
        default: failure,
      },
    },
    post: {
      tags: ["Virtual machines"],
      summary: "Run a host setup step",
      description: "Only one job runs at a time; `409` means one is already running or already satisfied.",
      operationId: "startVMSetup",
      requestBody: jsonBody(schemaRef("VMSetupRequest")),
      responses: {
        202: { description: "Setup job accepted", content: { "application/json": { schema: schemaRef("VMSetupJobResponse") } } },
        400: badRequest,
        401: unauthorized,
        409: {
          description: "A setup job is already running or the step is already satisfied.",
          content: { "application/json": { schema: schemaRef("ErrorResponse") } },
        },
        default: failure,
      },
    },
  },

  "/api/vms/setup/cancel": {
    post: {
      tags: ["Virtual machines"],
      summary: "Cancel the running setup job",
      operationId: "cancelVMSetup",
      responses: {
        200: ok(schemaRef("VMSetupJobResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/vms/setup/logs": {
    get: {
      tags: ["Virtual machines"],
      summary: "Stored setup logs, including rotated runs",
      operationId: "listVMSetupLogs",
      responses: {
        200: ok(schemaRef("VMSetupLogFilesResponse")),
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/vms/setup/log": {
    get: {
      tags: ["Virtual machines"],
      summary: "Latest setup log tail",
      operationId: "getVMSetupLog",
      parameters: [
        queryParam("step", "Log category.", { type: "string", enum: ["nix", "helper", "builder"] }),
        queryParam("tail", "Lines to return (1–2000). Defaults to 240.", {
          type: "integer", minimum: 1, maximum: 2000, default: 240,
        }),
      ],
      responses: {
        200: ok(schemaRef("VMSetupLogResultResponse")),
        400: badRequest,
        401: unauthorized,
        default: failure,
      },
    },
  },

  "/api/vms/{id}": {
    get: {
      tags: ["Virtual machines"],
      summary: "One virtual machine",
      operationId: "getVM",
      parameters: [
        pathParam("id", "VM id."),
        refreshParam,
      ],
      responses: {
        200: ok(schemaRef("VirtualMachineResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
    patch: {
      tags: ["Virtual machines"],
      summary: "Rename, resize, or replace packages",
      description: "CPU and memory can only change while the VM is stopped. Package changes while running queue an apply.",
      operationId: "updateVM",
      parameters: [pathParam("id", "VM id.")],
      requestBody: jsonBody(schemaRef("VMUpdateRequest")),
      responses: {
        200: ok(schemaRef("VirtualMachineResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
    delete: {
      tags: ["Virtual machines"],
      summary: "Remove a virtual machine",
      operationId: "deleteVM",
      parameters: [
        pathParam("id", "VM id."),
        queryParam("force", "Remove even when a disk exists or the helper is running.", {
          type: "string", enum: ["1"],
        }),
      ],
      responses: {
        200: ok(schemaRef("OkResponse")),
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/vms/{id}/{action}": {
    post: {
      tags: ["Virtual machines"],
      summary: "Control a virtual machine",
      description:
        "`rebuild` requires `force` when a disk exists; `apply` needs a running guest.",
      operationId: "controlVM",
      parameters: [
        pathParam("id", "VM id."),
        pathParam("action", "Lifecycle action.", {
          type: "string",
          enum: ["start", "stop", "restart", "pause", "resume", "rebuild", "apply"],
        }),
        queryParam("force", "Force the action where supported.", {
          type: "string", enum: ["1"],
        }),
      ],
      requestBody: jsonBody(schemaRef("VMForceRequest"), false),
      responses: {
        200: ok(schemaRef("VirtualMachineResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        409: {
          description: "The VM is in a state that cannot accept this action.",
          content: { "application/json": { schema: schemaRef("ErrorResponse") } },
        },
        default: failure,
      },
    },
  },

  "/api/vms/{id}/preview": {
    post: {
      tags: ["Virtual machines"],
      summary: "Preview a configuration for an existing VM",
      description:
        "Renders the configuration with this VM's hostname, SSH key, state version, and disk size. Nothing is written or applied.",
      operationId: "previewVMConfigForVM",
      parameters: [pathParam("id", "VM id.")],
      requestBody: jsonBody(schemaRef("VMConfigPreviewRequest"), false),
      responses: {
        200: ok(schemaRef("VMConfigPreviewResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/vms/{id}/log": {
    get: {
      tags: ["Virtual machines"],
      summary: "Build, serial, or apply log tail",
      operationId: "getVMLog",
      parameters: [
        pathParam("id", "VM id."),
        queryParam("type", "Log to read. Defaults to `build`.", {
          type: "string", enum: ["build", "serial", "apply"], default: "build",
        }),
        queryParam("tail", "Lines to return (1–2000). Defaults to 240.", {
          type: "integer", minimum: 1, maximum: 2000, default: 240,
        }),
      ],
      responses: {
        200: ok(schemaRef("VMLogResponse")),
        400: badRequest,
        401: unauthorized,
        404: notFound,
        default: failure,
      },
    },
  },

  "/api/vms/{id}/console/socket": {
    get: {
      tags: ["Virtual machines"],
      summary: "Serial console WebSocket",
      description:
        "Sends the last 64 KiB of boot output, then raw serial bytes. Text frames from the client are written to the guest.",
      operationId: "vmConsoleSocket",
      parameters: [pathParam("id", "VM id.")],
      responses: {
        101: { description: "Switching Protocols; serial console attached" },
        401: unauthorized,
        404: notFound,
        409: {
          description: "The VM is not running.",
          content: { "application/json": { schema: schemaRef("ErrorResponse") } },
        },
        501: unavailable,
      },
    },
  },
} as const;

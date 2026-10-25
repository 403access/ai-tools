/**
 * OpenAPI schemas for the hub's REST API.
 *
 * These mirror the wire types in `types.ts`; fields that OpenCode owns stay
 * permissive because the service can add fields before the hub knows about
 * them. Every schema is intentionally self-describing so Swagger UI can render
 * useful request and response examples.
 */

const number = { type: "number" } as const;
const integer = { type: "integer" } as const;
const string = { type: "string" } as const;
const bool = { type: "boolean" } as const;
const stringArray = { type: "array", items: { type: "string" } } as const;

const timestamp = {
  type: "integer",
  format: "int64",
  description: "Milliseconds since the Unix epoch.",
} as const;

const data = (schema: Record<string, unknown>) => ({
  type: "object",
  required: ["data"],
  properties: { data: schema },
});

const okRef = { $ref: "#/components/schemas/OkResponse" };
const sessionRef = { $ref: "#/components/schemas/Session" };
const terminalRef = { $ref: "#/components/schemas/Terminal" };
const vmRef = { $ref: "#/components/schemas/VirtualMachine" };
const fileEntryRef = { $ref: "#/components/schemas/HostFileEntry" };

export const SCHEMAS = {
  ErrorResponse: {
    type: "object",
    required: ["error"],
    properties: {
      error: {
        type: "object",
        required: ["message"],
        properties: {
          message: { type: "string" },
          code: { type: "string" },
        },
      },
    },
    example: { error: { message: "Session not found" } },
  },

  OkResponse: {
    type: "object",
    required: ["ok"],
    properties: {
      ok: { type: "boolean" },
      restarting: { type: "boolean" },
      hub: { $ref: "#/components/schemas/HubHealth" },
    },
    example: { ok: true },
  },

  TokenUsage: {
    type: "object",
    required: ["input", "output", "reasoning", "cache"],
    properties: {
      input: integer,
      output: integer,
      reasoning: integer,
      cache: {
        type: "object",
        required: ["read", "write"],
        properties: { read: integer, write: integer },
      },
    },
  },

  ModelRef: {
    type: "object",
    required: ["id", "providerID"],
    properties: {
      id: string,
      providerID: string,
      variant: string,
    },
  },

  SessionTime: {
    type: "object",
    required: ["created", "updated"],
    properties: {
      created: timestamp,
      updated: timestamp,
      idle: timestamp,
      viewed: timestamp,
      archived: timestamp,
    },
  },

  Session: {
    type: "object",
    required: ["id", "projectID", "cost", "tokens", "time"],
    properties: {
      id: { type: "string", example: "ses_01JABCDEF" },
      parentID: { type: "string", description: "Set for child/subagent sessions." },
      projectID: { type: "string", example: "prj_01JABCDEF" },
      agent: string,
      model: { $ref: "#/components/schemas/ModelRef" },
      cost: number,
      tokens: { $ref: "#/components/schemas/TokenUsage" },
      outcome: string,
      time: { $ref: "#/components/schemas/SessionTime" },
      title: string,
      subpath: string,
      location: {
        type: "object",
        properties: { directory: string },
      },
    },
    example: {
      id: "ses_01JABCDEF",
      projectID: "prj_01JABCDEF",
      cost: 1.24,
      tokens: { input: 120000, output: 8000, reasoning: 2000, cache: { read: 40000, write: 1000 } },
      time: { created: 1792900000000, updated: 1792903600000 },
      title: "Fix the build",
      location: { directory: "/Users/you/src/app" },
    },
  },

  ProjectTime: {
    type: "object",
    required: ["created", "updated"],
    properties: { created: timestamp, updated: timestamp, active: timestamp },
  },

  Project: {
    type: "object",
    required: ["id", "canonical", "time", "sandboxes"],
    properties: {
      id: { type: "string", example: "prj_01JABCDEF" },
      canonical: { type: "string", description: "Absolute path of the project root." },
      vcs: { type: "string", example: "git" },
      name: string,
      time: { $ref: "#/components/schemas/ProjectTime" },
      sandboxes: stringArray,
    },
  },

  ToolTotals: {
    type: "object",
    required: ["calls", "succeeded", "failed", "unfinished"],
    properties: {
      calls: integer,
      succeeded: integer,
      failed: integer,
      unfinished: integer,
    },
  },

  ToolUsage: {
    allOf: [
      { $ref: "#/components/schemas/ToolTotals" },
      {
        type: "object",
        required: ["name"],
        properties: {
          name: string,
          durationP50: { type: "integer", description: "Median duration in milliseconds." },
        },
      },
    ],
  },

  ToolsSummary: {
    type: "object",
    required: ["mode"],
    properties: {
      mode: { type: "string", enum: ["none", "summary", "detail"] },
      totals: { $ref: "#/components/schemas/ToolTotals" },
      usage: { type: "array", items: { $ref: "#/components/schemas/ToolUsage" } },
    },
  },

  Stats: {
    type: "object",
    description: "Global statistics from OpenCode's experimental stats endpoint.",
    additionalProperties: true,
    properties: {
      range: {
        type: "object",
        properties: { from: timestamp, to: timestamp },
      },
      sessions: integer,
      subagents: integer,
      prompts: integer,
      steps: integer,
      tokens: { $ref: "#/components/schemas/TokenUsage" },
      cost: number,
      tools: { $ref: "#/components/schemas/ToolsSummary" },
      activeDays: integer,
      streak: integer,
      activity: {
        type: "array",
        items: {
          type: "object",
          properties: { date: string, steps: integer },
        },
      },
      models: { type: "array", items: { type: "object", additionalProperties: true } },
    },
  },

  ToolFailure: {
    type: "object",
    required: ["name", "created"],
    properties: {
      name: string,
      error: string,
      messageID: string,
      partID: string,
      created: timestamp,
    },
  },

  SessionStats: {
    type: "object",
    required: [
      "sessionID", "prompts", "steps", "subagents", "messages", "tokens",
      "cost", "tools", "failures", "files", "time", "complete",
    ],
    properties: {
      sessionID: string,
      prompts: integer,
      steps: integer,
      subagents: integer,
      messages: integer,
      tokens: { $ref: "#/components/schemas/TokenUsage" },
      cost: number,
      tools: { $ref: "#/components/schemas/ToolsSummary" },
      failures: { type: "array", items: { $ref: "#/components/schemas/ToolFailure" } },
      files: {
        type: "object",
        required: ["files", "additions", "deletions"],
        properties: { files: integer, additions: integer, deletions: integer },
      },
      time: {
        type: "object",
        required: ["created", "updated", "duration"],
        properties: {
          created: timestamp,
          updated: timestamp,
          duration: integer,
          idle: integer,
        },
      },
      complete: { type: "boolean", description: "False when only part of the history is cached." },
    },
  },

  MessagePart: {
    type: "object",
    required: ["type"],
    additionalProperties: true,
    properties: {
      type: { type: "string", example: "text" },
      id: string,
      text: string,
      name: { type: "string", description: "Tool name for tool parts." },
      state: {
        type: "object",
        additionalProperties: true,
        properties: {
          status: string,
          input: {},
          content: { type: "array", items: { $ref: "#/components/schemas/MessagePart" } },
          metadata: {},
          error: {},
        },
      },
      time: {
        type: "object",
        properties: { created: timestamp, ran: timestamp, completed: timestamp },
      },
    },
  },

  SessionMessage: {
    type: "object",
    required: ["id", "type", "time"],
    additionalProperties: true,
    properties: {
      id: string,
      type: { type: "string", enum: ["user", "assistant", "system"] },
      time: {
        type: "object",
        required: ["created"],
        properties: {
          created: timestamp,
          streamed: timestamp,
          completed: timestamp,
        },
      },
      text: string,
      content: { type: "array", items: { $ref: "#/components/schemas/MessagePart" } },
      model: { $ref: "#/components/schemas/ModelRef" },
      agent: string,
      cost: number,
      tokens: { $ref: "#/components/schemas/TokenUsage" },
    },
  },

  MessageCursor: {
    type: "object",
    properties: { previous: string, next: string },
  },

  MessagesResponse: {
    type: "object",
    required: ["data"],
    properties: {
      data: { type: "array", items: { $ref: "#/components/schemas/SessionMessage" } },
      cursor: { $ref: "#/components/schemas/MessageCursor" },
    },
  },

  SessionsResponse: {
    type: "object",
    required: ["data"],
    properties: {
      data: { type: "array", items: sessionRef },
      cursor: { $ref: "#/components/schemas/MessageCursor" },
    },
  },

  ActiveSessionsResponse: {
    type: "object",
    required: ["data"],
    properties: {
      data: {
        type: "object",
        additionalProperties: {
          type: "object",
          properties: { type: { type: "string", example: "running" } },
        },
      },
    },
  },

  FileDiff: {
    type: "object",
    required: ["additions", "deletions"],
    properties: {
      file: string,
      patch: string,
      additions: integer,
      deletions: integer,
      status: { type: "string", enum: ["added", "deleted", "modified"] },
      sessionID: { type: "string", description: "Set when aggregated for a project." },
      sessionTitle: string,
      messageID: string,
      created: timestamp,
    },
  },

  ChangesResponse: {
    type: "object",
    required: ["data"],
    properties: { data: { type: "array", items: { $ref: "#/components/schemas/FileDiff" } } },
  },

  ProjectFile: {
    type: "object",
    required: ["path"],
    properties: {
      path: string,
      status: { type: "string", enum: ["added", "modified", "deleted", "renamed"] },
    },
  },

  ProjectFiles: {
    type: "object",
    required: ["files", "vcs", "changed", "total", "truncated"],
    properties: {
      files: { type: "array", items: { $ref: "#/components/schemas/ProjectFile" } },
      vcs: { type: "string", nullable: true, example: "git" },
      changed: integer,
      total: integer,
      truncated: bool,
    },
  },

  SessionPendingItem: {
    type: "object",
    required: ["id", "sessionID", "type", "time"],
    additionalProperties: true,
    properties: {
      id: string,
      sessionID: string,
      type: string,
      time: {
        type: "object",
        required: ["created"],
        properties: { created: timestamp },
      },
      delivery: { type: "string", enum: ["steer", "queue"] },
      payload: {
        type: "object",
        additionalProperties: true,
        properties: { text: string },
      },
    },
  },

  SyncResponse: {
    type: "object",
    required: [
      "revision", "full", "sessions", "deletedSessions", "projects",
      "deletedProjects", "active",
    ],
    properties: {
      revision: { type: "integer", description: "Send this back as `since` on the next poll." },
      full: { type: "boolean", description: "True when clients must replace their local copy." },
      sessions: { type: "array", items: sessionRef },
      deletedSessions: stringArray,
      projects: { type: "array", items: { $ref: "#/components/schemas/Project" } },
      deletedProjects: stringArray,
      active: { type: "array", items: string, description: "Always sent in full." },
    },
  },

  StatsResponse: {
    type: "object",
    required: ["data"],
    properties: {
      data: { $ref: "#/components/schemas/Stats" },
      fetchedAt: timestamp,
      stale: bool,
    },
  },

  GoUsageWindow: {
    type: "object",
    properties: {
      status: string,
      percent: number,
      resetsAt: { type: "string", format: "date-time" },
    },
  },

  GoUsage: {
    type: "object",
    properties: {
      rolling: { $ref: "#/components/schemas/GoUsageWindow" },
      weekly: { $ref: "#/components/schemas/GoUsageWindow" },
      monthly: { $ref: "#/components/schemas/GoUsageWindow" },
    },
  },

  UsageResponse: {
    type: "object",
    required: ["data", "fetchedAt", "stale", "error", "configured"],
    properties: {
      data: {
        type: "object",
        nullable: true,
        allOf: [{ $ref: "#/components/schemas/GoUsage" }],
      },
      fetchedAt: { ...timestamp, nullable: true },
      stale: bool,
      error: { type: "string", nullable: true },
      configured: bool,
    },
  },

  OpenCodeHealth: {
    type: "object",
    required: ["connected", "url", "version", "lastSync", "lastError"],
    properties: {
      connected: bool,
      url: { type: "string", nullable: true },
      version: { type: "string", nullable: true },
      lastSync: { ...timestamp, nullable: true },
      lastError: { type: "string", nullable: true },
    },
  },

  HubHealth: {
    type: "object",
    required: ["version", "uptime", "db", "sessions", "messages", "projects", "opencode"],
    properties: {
      version: string,
      uptime: number,
      db: { type: "string", description: "SQLite database path." },
      sessions: integer,
      messages: integer,
      projects: integer,
      opencode: { $ref: "#/components/schemas/OpenCodeHealth" },
    },
  },

  HealthResponse: {
    type: "object",
    required: ["ok", "version", "hub", "opencode"],
    properties: {
      ok: { type: "boolean" },
      version: string,
      hub: { $ref: "#/components/schemas/HubHealth" },
      opencode: { $ref: "#/components/schemas/OpenCodeHealth" },
    },
  },

  ServerInfo: {
    type: "object",
    properties: {
      version: string,
      pid: integer,
      urls: stringArray,
      capabilities: {
        type: "object",
        properties: { persistentPty: bool },
      },
      hub: { $ref: "#/components/schemas/HubHealth" },
    },
  },

  Terminal: {
    type: "object",
    required: ["id", "title", "command", "args", "cwd", "status", "pid", "location"],
    properties: {
      id: string,
      title: string,
      command: string,
      args: stringArray,
      cwd: string,
      status: { type: "string", enum: ["running", "exited"] },
      pid: integer,
      exitCode: integer,
      location: { type: "string", description: "OpenCode location (working directory) that owns this PTY." },
    },
  },

  TerminalCreateRequest: {
    type: "object",
    properties: {
      title: string,
      cwd: string,
      command: string,
      args: stringArray,
      location: { type: "string", description: "Defaults to the service's default location." },
      env: { type: "object", additionalProperties: { type: "string" } },
    },
    example: { title: "Tests", cwd: "/Users/you/src/app", command: "/bin/zsh" },
  },

  TerminalUpdateRequest: {
    type: "object",
    properties: {
      title: string,
      size: {
        type: "object",
        required: ["rows", "cols"],
        properties: {
          rows: { type: "integer", minimum: 1, maximum: 5000 },
          cols: { type: "integer", minimum: 1, maximum: 5000 },
        },
      },
      location: string,
    },
  },

  TerminalResponse: data(terminalRef),

  TerminalsResponse: data({ type: "array", items: terminalRef }),

  HostTerminal: {
    type: "object",
    required: ["id", "tty", "app", "title", "busy", "processes", "window", "tab"],
    properties: {
      id: { type: "string", example: "ttys001" },
      tty: { type: "string", example: "/dev/ttys001" },
      app: { type: "string", example: "Terminal" },
      title: string,
      busy: bool,
      processes: stringArray,
      window: integer,
      tab: integer,
    },
  },

  HostTerminalDetail: {
    allOf: [
      { $ref: "#/components/schemas/HostTerminal" },
      {
        type: "object",
        required: ["contents"],
        properties: {
          contents: { type: "string", description: "Plain-text mirror of the visible screen." },
          history: { type: "string", description: "Scrollback, only with `history=1`." },
        },
      },
    ],
  },

  HostTerminalsResponse: data({ type: "array", items: { $ref: "#/components/schemas/HostTerminal" } }),

  HostTerminalResponse: data({ $ref: "#/components/schemas/HostTerminalDetail" }),

  HostTerminalCommandRequest: {
    type: "object",
    required: ["command"],
    properties: {
      command: { type: "string", description: "Line to type into the tab; empty presses Return." },
    },
    example: { command: "npm run build" },
  },

  Device: {
    type: "object",
    required: ["id", "name", "platform", "appVersion", "firstSeen", "lastSeen", "connected"],
    properties: {
      id: string,
      name: string,
      platform: string,
      appVersion: string,
      firstSeen: timestamp,
      lastSeen: timestamp,
      connected: bool,
    },
  },

  DevicesResponse: data({ type: "array", items: { $ref: "#/components/schemas/Device" } }),

  HubSettings: {
    type: "object",
    required: [
      "eventThrottleMs", "eventThrottleMinMs", "eventThrottleMaxMs",
      "preventSleep", "preventSleepSupported",
    ],
    properties: {
      eventThrottleMs: { type: "integer", minimum: 0, maximum: 5000 },
      eventThrottleMinMs: integer,
      eventThrottleMaxMs: integer,
      preventSleep: bool,
      preventSleepSupported: bool,
    },
  },

  HubSettingsResponse: data({ $ref: "#/components/schemas/HubSettings" }),

  SettingsPatch: {
    type: "object",
    minProperties: 1,
    properties: {
      eventThrottleMs: { type: "integer", minimum: 0, maximum: 5000 },
      preventSleep: bool,
    },
    example: { eventThrottleMs: 500, preventSleep: true },
  },

  CreateSessionRequest: {
    type: "object",
    required: ["location"],
    properties: {
      title: string,
      location: {
        type: "object",
        required: ["directory"],
        properties: { directory: { type: "string", description: "Absolute project directory." } },
      },
    },
    example: {
      title: "Fix the build",
      location: { directory: "/Users/you/src/app" },
    },
  },

  PromptRequest: {
    type: "object",
    required: ["text"],
    properties: {
      text: string,
      delivery: {
        type: "string",
        enum: ["steer", "queue"],
        description: "`queue` waits for the current turn; `steer` asks OpenCode to steer it.",
      },
    },
    example: { text: "Run the test suite", delivery: "queue" },
  },

  SessionResponse: data(sessionRef),
  SessionChildrenResponse: data({ type: "array", items: sessionRef }),
  SessionStatsResponse: data({ $ref: "#/components/schemas/SessionStats" }),
  ProjectResponse: { $ref: "#/components/schemas/Project" },
  ProjectsResponse: {
    type: "array",
    items: { $ref: "#/components/schemas/Project" },
    description: "OpenCode returns projects as a plain array, not a `{ data }` envelope.",
  },
  ProjectFilesResponse: data({ $ref: "#/components/schemas/ProjectFiles" }),
  PendingInputsResponse: data({ type: "array", items: { $ref: "#/components/schemas/SessionPendingItem" } }),

  SystemApp: {
    type: "object",
    additionalProperties: true,
    properties: {
      name: string,
      path: string,
      bundleID: string,
      version: string,
      hasIcon: bool,
    },
  },

  SystemInfo: {
    type: "object",
    required: ["generatedAt", "platform", "platformName", "host", "hub", "cpu", "memory", "disks", "network", "processes"],
    additionalProperties: true,
    description:
      "A snapshot of the hub host. Collectors are platform-specific, so optional sections may be null or omitted.",
    properties: {
      generatedAt: timestamp,
      platform: { type: "string", example: "darwin" },
      platformName: { type: "string", example: "macOS" },
      host: { type: "object", additionalProperties: true },
      hub: { type: "object", additionalProperties: true },
      cpu: { type: "object", additionalProperties: true },
      memory: { type: "object", additionalProperties: true },
      disks: { type: "array", items: { type: "object", additionalProperties: true } },
      network: { type: "object", additionalProperties: true },
      processes: { type: "object", additionalProperties: true },
      battery: { type: "object", additionalProperties: true, nullable: true },
      thermal: { type: "object", additionalProperties: true, nullable: true },
      security: { type: "object", additionalProperties: true, nullable: true },
      apps: { type: "array", items: { $ref: "#/components/schemas/SystemApp" } },
      homebrew: { type: "object", additionalProperties: true, nullable: true },
      runtimes: { type: "array", items: { type: "object", additionalProperties: true } },
      displays: { type: "array", items: { type: "object", additionalProperties: true } },
      listeningPorts: { type: "array", items: { type: "object", additionalProperties: true } },
      docker: { type: "object", additionalProperties: true, nullable: true },
      media: { type: "array", items: { type: "object", additionalProperties: true } },
    },
  },

  SystemInfoResponse: data({ $ref: "#/components/schemas/SystemInfo" }),

  SystemAppDetail: {
    type: "object",
    additionalProperties: true,
    description:
      "Bundle facts plus provider-specific inventory. Xcode includes SDKs, frameworks, and simulator runtimes.",
    properties: {
      app: { $ref: "#/components/schemas/SystemApp" },
      info: { type: "object", additionalProperties: true },
      xcode: { type: "object", additionalProperties: true },
    },
  },

  SystemAppDetailResponse: data({ $ref: "#/components/schemas/SystemAppDetail" }),

  SystemAppActionRequest: {
    type: "object",
    required: ["path", "action"],
    properties: {
      path: { type: "string", description: "Application path from the system snapshot." },
      action: {
        type: "string",
        enum: [
          "simulator.boot",
          "simulator.shutdown",
          "simulator.erase",
          "simulator.delete",
          "runtime.delete",
        ],
      },
      target: { type: "string", description: "Simulator device UDID or runtime identifier." },
    },
    example: { path: "/Applications/Xcode.app", action: "simulator.boot", target: "1A2B3C4D-…" },
  },

  MediaControlResult: {
    type: "object",
    additionalProperties: true,
    properties: {
      media: { type: "array", items: { type: "object", additionalProperties: true } },
      audio: { type: "object", additionalProperties: true },
    },
  },

  MediaControlResponse: data({ $ref: "#/components/schemas/MediaControlResult" }),

  MediaRequest: {
    type: "object",
    required: ["action"],
    properties: {
      action: {
        type: "string",
        enum: [
          "toggle", "play", "pause", "next", "previous",
          "back15", "forward15", "mute", "volume",
        ],
      },
      value: { type: "number", description: "Required for `volume` (0–100); `1`/`0` for mute." },
    },
    example: { action: "volume", value: 65 },
  },

  HostFileRoot: {
    type: "object",
    required: ["name", "path"],
    properties: { name: string, path: string, kind: string },
  },

  HostFileEntry: {
    type: "object",
    required: ["name", "path", "kind", "isDirectory", "hidden"],
    properties: {
      name: string,
      path: string,
      kind: { type: "string", enum: ["directory", "file", "symlink", "other"] },
      isDirectory: bool,
      size: integer,
      modified: timestamp,
      permissions: string,
      hidden: bool,
      linkTarget: string,
      error: string,
    },
  },

  HostDirectory: {
    type: "object",
    required: ["path", "name", "parent", "roots", "entries", "total", "truncated"],
    properties: {
      path: string,
      name: string,
      parent: { type: "string", nullable: true },
      roots: { type: "array", items: { $ref: "#/components/schemas/HostFileRoot" } },
      entries: { type: "array", items: fileEntryRef },
      total: integer,
      truncated: bool,
    },
  },

  HostDirectoryResponse: data({ $ref: "#/components/schemas/HostDirectory" }),

  HostFileContent: {
    type: "object",
    required: ["path", "name", "size", "modified", "kind", "mime", "truncated", "maxBytes"],
    properties: {
      path: string,
      name: string,
      size: integer,
      modified: timestamp,
      kind: { type: "string", enum: ["text", "image", "binary"] },
      mime: string,
      content: { type: "string", description: "Up to 512 KB of text, when `kind` is `text`." },
      truncated: bool,
      maxBytes: integer,
    },
  },

  HostFileContentResponse: data({ $ref: "#/components/schemas/HostFileContent" }),

  RemoteDisplay: {
    type: "object",
    required: ["id", "name", "width", "height", "scale", "primary"],
    properties: {
      id: integer,
      name: string,
      width: integer,
      height: integer,
      scale: number,
      primary: bool,
    },
  },

  RemoteStatus: {
    type: "object",
    required: [
      "available", "running", "viewers", "version", "screenRecording",
      "accessibility", "displays", "displayID", "fps", "quality", "maxWidth",
      "streaming", "error",
    ],
    properties: {
      available: bool,
      running: bool,
      viewers: integer,
      version: { type: "string", nullable: true },
      screenRecording: bool,
      accessibility: bool,
      displays: { type: "array", items: { $ref: "#/components/schemas/RemoteDisplay" } },
      displayID: { type: "integer", nullable: true },
      fps: number,
      quality: number,
      maxWidth: integer,
      streaming: bool,
      error: { type: "string", nullable: true },
    },
  },

  RemoteStatusResponse: data({ $ref: "#/components/schemas/RemoteStatus" }),

  RemoteConfigureRequest: {
    type: "object",
    minProperties: 1,
    properties: {
      fps: number,
      quality: { type: "number", minimum: 0, maximum: 1 },
      maxWidth: integer,
      displayID: integer,
    },
    example: { fps: 8, quality: 0.45, maxWidth: 1280 },
  },

  RemotePermissionsRequest: {
    type: "object",
    properties: {
      screenRecording: bool,
      accessibility: bool,
    },
  },

  VMStatus: {
    type: "string",
    enum: ["building", "stopped", "starting", "running", "stopping", "paused", "error"],
  },

  VMProgress: {
    type: "object",
    required: ["phase", "message", "startedAt"],
    properties: { phase: string, message: string, startedAt: timestamp },
  },

  VMHostMetrics: {
    type: "object",
    additionalProperties: true,
    properties: {
      cpuPercent: number,
      rssBytes: integer,
      diskBytes: integer,
      diskUsedBytes: integer,
      uptimeSec: number,
    },
  },

  VMGuestMetrics: {
    type: "object",
    additionalProperties: true,
    required: ["reachable"],
    properties: {
      reachable: bool,
      uptimeSec: number,
      cpuPercent: number,
      load1: number,
      load5: number,
      load15: number,
      memoryTotalBytes: integer,
      memoryUsedBytes: integer,
      memoryAvailableBytes: integer,
      swapUsedBytes: integer,
      diskTotalBytes: integer,
      diskUsedBytes: integer,
      diskAvailableBytes: integer,
      hostname: string,
      kernel: string,
      generation: string,
      error: string,
    },
  },

  VMMetrics: {
    type: "object",
    required: ["collectedAt"],
    properties: {
      collectedAt: timestamp,
      state: string,
      host: { $ref: "#/components/schemas/VMHostMetrics" },
      guest: { $ref: "#/components/schemas/VMGuestMetrics" },
    },
  },

  VMSshInfo: {
    type: "object",
    required: ["user", "keyPath", "publicKey"],
    properties: { user: string, keyPath: string, publicKey: string },
  },

  VMNetworkInfo: {
    type: "object",
    required: ["mac", "ip", "reachable"],
    properties: {
      mac: string,
      ip: { type: "string", nullable: true },
      reachable: bool,
    },
  },

  VMPaths: {
    type: "object",
    required: ["directory", "disk", "configuration", "flake", "serialLog", "buildLog", "applyLog", "runtime"],
    properties: {
      directory: string,
      disk: string,
      configuration: string,
      flake: string,
      serialLog: string,
      buildLog: string,
      applyLog: string,
      runtime: string,
    },
  },

  VirtualMachine: {
    type: "object",
    required: [
      "id", "name", "distro", "channel", "stateVersion", "arch", "status",
      "createdAt", "updatedAt", "cpuCount", "memoryMB", "diskGB", "packages",
      "pendingPackages", "pendingConfig", "config", "lastError", "progress",
      "ssh", "network", "paths",
    ],
    properties: {
      id: string,
      name: string,
      distro: { type: "string", enum: ["nixos"] },
      channel: string,
      stateVersion: string,
      arch: string,
      status: { $ref: "#/components/schemas/VMStatus" },
      createdAt: timestamp,
      updatedAt: timestamp,
      cpuCount: integer,
      memoryMB: integer,
      diskGB: number,
      packages: stringArray,
      pendingPackages: stringArray,
      pendingConfig: bool,
      config: { $ref: "#/components/schemas/NixOSBuilderConfig" },
      lastError: { type: "string", nullable: true },
      progress: {
        type: "object",
        nullable: true,
        allOf: [{ $ref: "#/components/schemas/VMProgress" }],
      },
      ssh: { $ref: "#/components/schemas/VMSshInfo" },
      network: { $ref: "#/components/schemas/VMNetworkInfo" },
      paths: { $ref: "#/components/schemas/VMPaths" },
      startedAt: timestamp,
      lastBootAt: timestamp,
      metrics: {
        type: "object",
        nullable: true,
        allOf: [{ $ref: "#/components/schemas/VMMetrics" }],
      },
    },
  },

  VirtualMachinesResponse: data({ type: "array", items: vmRef }),
  VirtualMachineResponse: data(vmRef),

  VMCapabilities: {
    type: "object",
    required: [
      "supported", "platform", "arch", "helperPath", "helperAvailable",
      "helperEntitled", "nixPath", "nixAvailable", "nixVersion", "linuxBuilder",
      "linuxBuilderDetail", "storageDir", "defaultChannel", "defaultCPU",
      "defaultMemoryMB", "maxCPU", "maxMemoryMB", "notes",
    ],
    properties: {
      supported: bool,
      platform: string,
      arch: string,
      helperPath: { type: "string", nullable: true },
      helperAvailable: bool,
      helperEntitled: bool,
      nixPath: { type: "string", nullable: true },
      nixAvailable: bool,
      nixVersion: { type: "string", nullable: true },
      linuxBuilder: bool,
      linuxBuilderDetail: { type: "string", nullable: true },
      storageDir: string,
      defaultChannel: string,
      defaultCPU: integer,
      defaultMemoryMB: integer,
      maxCPU: integer,
      maxMemoryMB: integer,
      notes: stringArray,
    },
  },

  VMCapabilitiesResponse: data({ $ref: "#/components/schemas/VMCapabilities" }),

  NixOSManagedUser: {
    type: "object",
    required: ["name", "description", "groups", "shell", "sshKeys", "passwordlessSudo", "createHome"],
    properties: {
      name: string,
      description: string,
      groups: stringArray,
      shell: { type: "string", enum: ["bash", "zsh", "fish"] },
      sshKeys: stringArray,
      passwordlessSudo: bool,
      createHome: bool,
    },
  },

  NixOSBuilderSettings: {
    type: "object",
    required: [
      "timezone", "locale", "keymap", "firewall", "passwordAuthentication",
      "extraTCPPorts", "extraUDPPorts",
    ],
    properties: {
      timezone: string,
      locale: string,
      keymap: string,
      firewall: bool,
      passwordAuthentication: bool,
      extraTCPPorts: { type: "array", items: integer },
      extraUDPPorts: { type: "array", items: integer },
    },
  },

  NixOSBuilderConfig: {
    type: "object",
    required: ["version", "preset", "enabled", "settings", "users", "extraPackages", "extraConfig"],
    properties: {
      version: { type: "integer", enum: [1] },
      preset: { type: "string", nullable: true },
      enabled: stringArray,
      settings: { $ref: "#/components/schemas/NixOSBuilderSettings" },
      users: {
        type: "array",
        items: { $ref: "#/components/schemas/NixOSManagedUser" },
      },
      extraPackages: stringArray,
      extraConfig: string,
    },
    example: {
      version: 1,
      preset: "developer",
      enabled: ["zram", "docker", "tailscale", "neovim", "nodejs"],
      settings: {
        timezone: "UTC",
        locale: "en_US.UTF-8",
        keymap: "us",
        firewall: true,
        passwordAuthentication: false,
        extraTCPPorts: [],
        extraUDPPorts: [],
      },
      users: [],
      extraPackages: ["ripgrep"],
      extraConfig: "",
    },
  },

  VMConfigCategory: {
    type: "object",
    required: ["id", "name", "summary", "icon", "tint"],
    properties: {
      id: string,
      name: string,
      summary: string,
      icon: string,
      tint: string,
    },
  },

  VMConfigOption: {
    type: "object",
    required: [
      "id", "category", "name", "summary", "description", "icon", "tint",
      "tags", "badge", "packages", "requires", "recommends", "conflicts",
      "ports", "services", "defaultOn", "locked", "sizeMB", "unfree",
    ],
    properties: {
      id: string,
      category: string,
      name: string,
      summary: string,
      description: string,
      icon: string,
      tint: string,
      tags: stringArray,
      badge: { type: "string", nullable: true },
      packages: stringArray,
      requires: stringArray,
      recommends: stringArray,
      conflicts: stringArray,
      ports: { type: "array", items: integer },
      services: stringArray,
      defaultOn: bool,
      locked: bool,
      sizeMB: integer,
      unfree: bool,
    },
  },

  VMConfigPreset: {
    type: "object",
    required: ["id", "name", "summary", "icon", "tint", "options", "tags"],
    properties: {
      id: string,
      name: string,
      summary: string,
      icon: string,
      tint: string,
      options: stringArray,
      tags: stringArray,
    },
  },

  VMConfigCatalog: {
    type: "object",
    required: [
      "version", "categories", "options", "presets", "defaults",
      "recommendedPreset", "shells", "groups", "timezones", "locales",
      "keymaps", "limits",
    ],
    properties: {
      version: { type: "integer", enum: [1] },
      categories: {
        type: "array",
        items: { $ref: "#/components/schemas/VMConfigCategory" },
      },
      options: {
        type: "array",
        items: { $ref: "#/components/schemas/VMConfigOption" },
      },
      presets: {
        type: "array",
        items: { $ref: "#/components/schemas/VMConfigPreset" },
      },
      defaults: { $ref: "#/components/schemas/NixOSBuilderConfig" },
      recommendedPreset: { type: "string", nullable: true },
      shells: stringArray,
      groups: stringArray,
      timezones: stringArray,
      locales: stringArray,
      keymaps: stringArray,
      limits: {
        type: "object",
        required: ["maxUsers", "maxExtraPackages", "maxExtraConfigBytes", "maxPorts"],
        properties: {
          maxUsers: integer,
          maxExtraPackages: integer,
          maxExtraConfigBytes: integer,
          maxPorts: integer,
        },
      },
    },
  },

  VMConfigPreview: {
    type: "object",
    required: [
      "configuration", "flake", "packages", "services", "ports", "users",
      "optionCount", "added", "warnings", "sizeMB", "stateVersion",
    ],
    properties: {
      configuration: string,
      flake: string,
      packages: stringArray,
      services: stringArray,
      ports: { type: "array", items: integer },
      users: stringArray,
      optionCount: integer,
      added: stringArray,
      warnings: stringArray,
      sizeMB: integer,
      stateVersion: string,
    },
  },

  VMConfigCatalogResponse: data({ $ref: "#/components/schemas/VMConfigCatalog" }),
  VMConfigPreviewResponse: data({ $ref: "#/components/schemas/VMConfigPreview" }),

  VMConfigPreviewRequest: {
    type: "object",
    properties: {
      config: { $ref: "#/components/schemas/NixOSBuilderConfig" },
      packages: stringArray,
      name: string,
      diskGB: number,
      channel: string,
      stateVersion: string,
    },
  },

  VMCreateRequest: {
    type: "object",
    required: ["name"],
    properties: {
      name: string,
      cpuCount: integer,
      memoryMB: integer,
      diskGB: number,
      channel: string,
      packages: stringArray,
      config: { $ref: "#/components/schemas/NixOSBuilderConfig" },
      autostart: { type: "boolean", default: true },
    },
    example: {
      name: "NixOS dev",
      cpuCount: 4,
      memoryMB: 4096,
      diskGB: 20,
      channel: "nixos-26.05",
      packages: ["nodejs", "ripgrep"],
      autostart: true,
    },
  },

  VMUpdateRequest: {
    type: "object",
    minProperties: 1,
    properties: {
      name: string,
      cpuCount: integer,
      memoryMB: integer,
      packages: stringArray,
      config: { $ref: "#/components/schemas/NixOSBuilderConfig" },
    },
  },

  VMForceRequest: {
    type: "object",
    properties: { force: bool },
  },

  VMLog: {
    type: "object",
    required: ["type", "path", "lines", "bytes", "truncated"],
    properties: {
      type: { type: "string", enum: ["build", "serial", "apply"] },
      path: string,
      lines: stringArray,
      bytes: integer,
      truncated: bool,
    },
  },

  VMLogResponse: data({ $ref: "#/components/schemas/VMLog" }),

  VMSetupLog: {
    type: "object",
    required: ["path", "lines", "bytes", "truncated"],
    properties: {
      path: string,
      lines: stringArray,
      bytes: integer,
      truncated: bool,
    },
  },

  VMSetupJob: {
    type: "object",
    required: [
      "step", "status", "command", "requiresAdmin", "startedAt",
      "finishedAt", "exitCode", "error", "log",
    ],
    properties: {
      step: { type: "string", enum: ["nix", "helper", "builder"] },
      status: { type: "string", enum: ["running", "succeeded", "failed", "cancelled"] },
      command: string,
      requiresAdmin: bool,
      startedAt: timestamp,
      finishedAt: { type: "integer", format: "int64", nullable: true },
      exitCode: { type: "integer", nullable: true },
      error: { type: "string", nullable: true },
      log: { $ref: "#/components/schemas/VMSetupLog" },
    },
  },

  VMSetupJobResponse: data({ $ref: "#/components/schemas/VMSetupJob" }),

  VMSetupRequest: {
    type: "object",
    required: ["step"],
    properties: {
      step: { type: "string", enum: ["nix", "helper"] },
    },
    example: { step: "nix" },
  },

  VMSetupLogFile: {
    type: "object",
    required: ["step", "path", "bytes", "modified"],
    properties: {
      step: { type: "string", enum: ["nix", "helper", "builder"] },
      path: string,
      bytes: integer,
      modified: timestamp,
    },
  },

  VMSetupLogFilesResponse: data({
    type: "array",
    items: { $ref: "#/components/schemas/VMSetupLogFile" },
  }),

  VMSetupLogResult: {
    type: "object",
    required: ["step", "path", "lines", "bytes", "truncated"],
    properties: {
      step: { type: "string", enum: ["nix", "helper", "builder"] },
      path: string,
      lines: stringArray,
      bytes: integer,
      truncated: bool,
    },
  },

  VMSetupLogResultResponse: data({ $ref: "#/components/schemas/VMSetupLogResult" }),

  EventStream: {
    type: "string",
    description:
      "Server-Sent Events stream. Each `data:` line is a JSON HubEvent; `: ping` comments arrive every 15 seconds.",
  },

  HubEvent: {
    type: "object",
    required: ["type"],
    additionalProperties: true,
    properties: {
      id: string,
      type: string,
      created: timestamp,
      data: { type: "object", additionalProperties: true },
    },
  },

  PingResponse: {
    type: "object",
    required: ["ok", "hub", "version"],
    properties: {
      ok: { type: "boolean" },
      hub: { type: "boolean" },
      version: string,
    },
    example: { ok: true, hub: true, version: "1.0.0" },
  },
} as const;

const SCHEMA_REF_PREFIX = "#/components/schemas/";

/** Returns the set of schema names referenced anywhere in a value. */
export function referencedSchemas(value: unknown, found = new Set<string>()): Set<string> {
  if (Array.isArray(value)) {
    for (const entry of value) referencedSchemas(entry, found);
  } else if (value && typeof value === "object") {
    for (const [key, entry] of Object.entries(value)) {
      if (key === "$ref" && typeof entry === "string" && entry.startsWith(SCHEMA_REF_PREFIX)) {
        found.add(entry.slice(SCHEMA_REF_PREFIX.length));
      } else {
        referencedSchemas(entry, found);
      }
    }
  }
  return found;
}

/**
 * Wire types shared with the OpenCode service and the native clients.
 *
 * Field names deliberately mirror OpenCode's JSON so the macOS and iOS apps can
 * decode hub responses with their existing models.
 */

export interface TokenUsage {
  input: number;
  output: number;
  reasoning: number;
  cache: { read: number; write: number };
}

export interface ModelRef {
  id: string;
  providerID: string;
  variant?: string;
}

export interface SessionTime {
  created: number;
  updated: number;
  idle?: number;
  viewed?: number;
  archived?: number;
}

export interface Session {
  id: string;
  parentID?: string;
  projectID: string;
  agent?: string;
  model?: ModelRef;
  cost: number;
  tokens: TokenUsage;
  outcome?: string;
  time: SessionTime;
  title?: string;
  subpath?: string;
  location: { directory?: string };
}

export interface ProjectTime {
  created: number;
  updated: number;
  active?: number;
}

export interface Project {
  id: string;
  canonical: string;
  vcs?: string;
  name?: string;
  time: ProjectTime;
  sandboxes: string[];
}

export interface ToolTotals {
  calls: number;
  succeeded: number;
  failed: number;
  unfinished: number;
}

/** One tool's reliability, as reported by the stats API with `tools=detail`. */
export interface ToolUsage extends ToolTotals {
  name: string;
  /** Median duration in milliseconds, when the service measured it. */
  durationP50?: number;
}

export interface ToolsSummary {
  mode: "none" | "summary" | "detail" | string;
  totals?: ToolTotals;
  usage?: ToolUsage[];
}

export interface Stats {
  range?: { from: number; to: number };
  sessions?: number;
  subagents?: number;
  prompts?: number;
  steps?: number;
  tokens?: TokenUsage;
  cost?: number;
  tools?: ToolsSummary;
  activeDays?: number;
  streak?: number;
  activity?: Array<{ date: string; steps: number }>;
  models?: unknown[];
  [key: string]: unknown;
}

/** A failed tool call, kept for the session's failure list. */
export interface ToolFailure {
  name: string;
  error?: string;
  messageID?: string;
  partID?: string;
  created: number;
}

/** Stats derived from a session's cached messages and tool calls. */
export interface SessionStats {
  sessionID: string;
  prompts: number;
  steps: number;
  subagents: number;
  messages: number;
  tokens: TokenUsage;
  cost: number;
  tools: ToolsSummary;
  failures: ToolFailure[];
  files: { files: number; additions: number; deletions: number };
  time: { created: number; updated: number; duration: number; idle?: number };
  /** False when only part of the message history has been cached. */
  complete: boolean;
}

export interface SessionStatsResponse {
  data: SessionStats;
}

export interface MessageTime {
  created: number;
  streamed?: number;
  completed?: number;
}

export interface MessagePart {
  type: string;
  id?: string;
  text?: string;
  name?: string;
  state?: {
    status?: string;
    input?: unknown;
    content?: MessagePart[];
    metadata?: unknown;
    error?: unknown;
  };
  time?: { created?: number; ran?: number; completed?: number };
}

export interface SessionMessage {
  id: string;
  type: string;
  time: MessageTime;
  text?: string;
  content?: MessagePart[];
  model?: ModelRef;
  agent?: string;
  cost?: number;
  tokens?: TokenUsage;
}

/** One file in a tool call's metadata, with the patch OpenCode produced. */
export interface FileDiff {
  file?: string;
  patch?: string;
  additions: number;
  deletions: number;
  status?: "added" | "deleted" | "modified";
  /** Set when the diff is aggregated for a project. */
  sessionID?: string;
  sessionTitle?: string;
  messageID?: string;
  created?: number;
}

export interface ChangesResponse {
  data: FileDiff[];
}

/** Working-tree state of a file, from `git status`. */
export type ProjectFileStatus = "added" | "modified" | "deleted" | "renamed";

/** One file inside a project directory. */
export interface ProjectFile {
  /** Path relative to the project root, using forward slashes. */
  path: string;
  /** Omitted when the file matches the index. */
  status?: ProjectFileStatus;
}

/** The project file browser payload. */
export interface ProjectFiles {
  files: ProjectFile[];
  /** `"git"` when status was read from a work tree, otherwise null. */
  vcs: string | null;
  /** Number of files with a status. */
  changed: number;
  /** Number of files before the response was capped. */
  total: number;
  /** True when `files` omits entries because the project is very large. */
  truncated: boolean;
}

export interface ProjectFilesResponse {
  data: ProjectFiles;
}

export interface MessageCursor {
  previous?: string;
  next?: string;
}

export interface MessagesResponse {
  data: SessionMessage[];
  cursor?: MessageCursor;
}

export interface SessionsResponse {
  data: Session[];
  cursor?: { previous?: string; next?: string };
}

export interface ActiveSessionsResponse {
  data: Record<string, { type: string }>;
}

export interface StatsResponse {
  data: Stats;
  fetchedAt?: number;
  stale?: boolean;
}

export interface GoUsageWindow {
  status?: string;
  percent?: number;
  resetsAt?: string;
}

export interface GoUsage {
  rolling?: GoUsageWindow;
  weekly?: GoUsageWindow;
  monthly?: GoUsageWindow;
}

export interface UsageResponse {
  data: GoUsage | null;
  fetchedAt: number | null;
  stale: boolean;
  error: string | null;
  configured: boolean;
}

export interface ServerInfo {
  version?: string;
  pid?: number;
  urls?: string[];
  capabilities?: { persistentPty?: boolean };
  hub?: HubHealth;
}

/** A Mac or iOS app that has talked to this hub. */
export interface ConnectedDevice {
  id: string;
  name: string;
  platform: string;
  appVersion: string;
  /** Milliseconds since the epoch. */
  firstSeen: number;
  lastSeen: number;
  /** True while the device has an event stream open or polled recently. */
  connected: boolean;
}

export interface DevicesResponse {
  data: ConnectedDevice[];
}

export interface HubHealth {
  version: string;
  uptime: number;
  db: string;
  sessions: number;
  messages: number;
  projects: number;
  opencode: {
    connected: boolean;
    url: string | null;
    version: string | null;
    lastSync: number | null;
    lastError: string | null;
  };
}

/** An event forwarded from OpenCode, or one emitted by the hub itself. */
export interface HubEvent {
  id?: string;
  type: string;
  created?: number;
  data?: Record<string, unknown>;
}

export const ZERO_TOKENS: TokenUsage = {
  input: 0,
  output: 0,
  reasoning: 0,
  cache: { read: 0, write: 0 },
};

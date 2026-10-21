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

export interface Stats {
  range?: { from: number; to: number };
  sessions?: number;
  subagents?: number;
  prompts?: number;
  steps?: number;
  tokens?: TokenUsage;
  cost?: number;
  tools?: unknown;
  activeDays?: number;
  streak?: number;
  activity?: Array<{ date: string; steps: number }>;
  models?: unknown[];
  [key: string]: unknown;
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

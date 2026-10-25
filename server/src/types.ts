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

/**
 * One admitted-but-undelivered session input. OpenCode keeps these in its
 * inbox until the running turn is ready for them.
 */
export interface SessionPendingItem {
  id: string;
  sessionID: string;
  type: string;
  time: { created: number };
  delivery?: "steer" | "queue";
  payload?: {
    text?: string;
    [key: string]: unknown;
  };
}

export interface SessionsResponse {
  data: Session[];
  cursor?: { previous?: string; next?: string };
}

export interface ActiveSessionsResponse {
  data: Record<string, { type: string }>;
}

/**
 * Incremental change feed for the native clients. `sessions` and `projects`
 * only contain rows that changed after the client's last revision; the deleted
 * arrays carry tombstones. A `full` response must replace the client's local
 * copy instead of merging into it.
 */
export interface SyncResponse {
  revision: number;
  full: boolean;
  sessions: Session[];
  deletedSessions: string[];
  projects: Project[];
  deletedProjects: string[];
  /** Sessions currently running, always sent in full (it is a short list). */
  active: string[];
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

// MARK: - Terminals

/**
 * One pseudo-terminal owned by the OpenCode service. The hub proxies the
 * service's PTYs so both apps can list and drive all terminal sessions on the
 * machine, including ones started from the OpenCode TUI.
 */
export interface Terminal {
  id: string;
  title: string;
  command: string;
  args: string[];
  cwd: string;
  status: "running" | "exited";
  pid: number;
  exitCode?: number;
  /** OpenCode location (working directory) that owns this terminal. */
  location: string;
}

export interface TerminalCreateInput {
  title?: string;
  cwd?: string;
  command?: string;
  args?: string[];
  location?: string;
  env?: Record<string, string>;
}

export interface TerminalUpdateInput {
  title?: string;
  size?: { rows: number; cols: number };
}

export interface TerminalsResponse {
  data: Terminal[];
}

export interface TerminalResponse {
  data: Terminal;
}

/**
 * A tab open in Terminal.app on the hub host. Unlike OpenCode PTYs these are
 * owned by the terminal emulator, so the hub can mirror their text and run
 * commands in them through macOS automation.
 */
export interface HostTerminal {
  /** Stable while the tab stays open, e.g. `ttys001`. */
  id: string;
  /** Device path, e.g. `/dev/ttys001`. */
  tty: string;
  /** Terminal application that owns the tab. Currently always `Terminal`. */
  app: string;
  title: string;
  busy: boolean;
  processes: string[];
  window: number;
  tab: number;
}

export interface HostTerminalDetail extends HostTerminal {
  /** Plain-text mirror of the tab's current screen. */
  contents: string;
  /** Full scrollback, only when explicitly requested. */
  history?: string;
}

export interface HostTerminalsResponse {
  data: HostTerminal[];
}

export interface HostTerminalResponse {
  data: HostTerminalDetail;
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

/**
 * Hub behaviour that the settings screen can tune without restarting. The
 * bounds are included so clients do not have to hard-code the accepted range.
 */
export interface HubSettings {
  /** Coalescing window for event-stream updates; `0` sends every event. */
  eventThrottleMs: number;
  eventThrottleMinMs: number;
  eventThrottleMaxMs: number;
  /** True while the hub keeps the host Mac from idle-sleeping. */
  preventSleep: boolean;
  /** False on platforms where the hub cannot block sleep. */
  preventSleepSupported: boolean;
}

export interface HubSettingsResponse {
  data: HubSettings;
}

// MARK: - System monitoring

/**
 * A full snapshot of the machine running the hub. Everything is optional
 * because collectors are platform-specific and can time out: a missing field
 * means "not available on this system", not "zero". Byte counts are bytes and
 * durations are seconds unless the field name says otherwise.
 */
export interface SystemInfo {
  generatedAt: number;
  platform: string;
  platformName: string;
  host: SystemHost;
  hub: SystemHub;
  cpu: SystemCPU;
  memory: SystemMemory;
  disks: SystemDisk[];
  network: SystemNetwork;
  processes: SystemProcesses;
  battery: SystemBattery | null;
  thermal: SystemThermal | null;
  security: SystemSecurity | null;
  apps: SystemApp[];
  homebrew: SystemHomebrew | null;
  runtimes: SystemRuntime[];
  displays: SystemDisplayGroup[];
  listeningPorts: SystemPort[];
  docker: SystemDocker | null;
  media: SystemMedia[];
  audio: SystemAudio | null;
  notes: string[];
}

export interface SystemHost {
  name: string;
  hostname: string;
  platform: string;
  platformName: string;
  osName?: string;
  osVersion?: string;
  osBuild?: string;
  kernel: string;
  arch: string;
  machine?: string;
  model?: string;
  chip?: string;
  username?: string;
  home?: string;
  shell?: string;
  timezone?: string;
  locale?: string;
  uptime: number;
  bootedAt?: number;
  isVirtualMachine?: boolean;
  virtualization?: string;
}

export interface SystemHub {
  version: string;
  pid: number;
  runtime: string;
  runtimeVersion: string;
  startedAt: number;
  uptime: number;
  port?: number;
  dbPath?: string;
  dbSizeBytes?: number;
  cwd?: string;
  execPath?: string;
  memoryBytes?: number;
  rssBytes?: number;
  heapUsedBytes?: number;
}

export interface SystemCPU {
  model?: string;
  vendor?: string;
  architecture: string;
  physicalCores?: number;
  logicalCores: number;
  speedMHz?: number;
  usagePercent?: number;
  perCoreUsage?: number[];
  loadAverage?: number[];
  temperatureC?: number;
}

export interface SystemMemory {
  totalBytes: number;
  freeBytes: number;
  usedBytes: number;
  availableBytes?: number;
  activeBytes?: number;
  inactiveBytes?: number;
  wiredBytes?: number;
  compressedBytes?: number;
  cachedBytes?: number;
  swapTotalBytes?: number;
  swapUsedBytes?: number;
  swapFreeBytes?: number;
}

export interface SystemDisk {
  mount: string;
  filesystem: string;
  type?: string;
  totalBytes: number;
  usedBytes: number;
  freeBytes: number;
  readOnly?: boolean;
  removable?: boolean;
}

export interface SystemNetworkAddress {
  address: string;
  family: string;
  internal: boolean;
  mac?: string;
  netmask?: string;
  cidr?: string;
}

export interface SystemNetworkInterface {
  name: string;
  addresses: SystemNetworkAddress[];
}

export interface SystemNetwork {
  hostname: string;
  interfaces: SystemNetworkInterface[];
  defaultGateway?: string;
  defaultInterface?: string;
  dnsServers: string[];
}

export interface SystemProcess {
  pid: number;
  name: string;
  command?: string;
  user?: string;
  cpuPercent?: number;
  memoryPercent?: number;
  memoryBytes?: number;
}

export interface SystemProcesses {
  total: number;
  topCPU: SystemProcess[];
  topMemory: SystemProcess[];
}

export interface SystemBattery {
  present: boolean;
  percent?: number;
  charging?: boolean;
  state?: string;
  minutesRemaining?: number;
  cycleCount?: number;
  condition?: string;
  healthPercent?: number;
  temperatureC?: number;
}

export interface SystemThermal {
  cpuSpeedLimitPercent?: number;
  cpuSchedulerLimitPercent?: number;
  pressure?: string;
  temperatureC?: number;
  sensors?: Array<{ name: string; temperatureC: number }>;
}

export interface SystemSecurity {
  systemIntegrityProtection?: boolean | string;
  fileVault?: boolean | string;
  firewall?: boolean | string;
  gatekeeper?: boolean | string;
  secureBoot?: boolean | string;
  selinux?: string;
  appArmor?: string;
  defender?: string;
}

export interface SystemApp {
  name: string;
  path: string;
  version?: string;
  bundleID?: string;
  source?: string;
  architecture?: string;
  lastModified?: string;
}

export interface SystemBrewPackage {
  name: string;
  version: string;
  kind: "formula" | "cask";
  outdated: boolean;
}

export interface SystemHomebrew {
  available: boolean;
  version?: string;
  prefix?: string;
  formulaCount: number;
  caskCount: number;
  outdatedCount: number;
  packages: SystemBrewPackage[];
}

export interface SystemRuntime {
  name: string;
  version?: string;
  path?: string;
  kind: "runtime" | "tool";
}

export interface SystemDisplay {
  name: string;
  resolution?: string;
  pixels?: string;
  type?: string;
  main?: boolean;
  online?: boolean;
  mirror?: boolean;
}

export interface SystemDisplayGroup {
  name: string;
  vendor?: string;
  model?: string;
  cores?: number;
  displays: SystemDisplay[];
}

export interface SystemPort {
  port: number;
  protocol: "tcp" | "udp";
  address?: string;
  process?: string;
  pid?: number;
}

export interface SystemContainer {
  id: string;
  name: string;
  image: string;
  state: string;
  status: string;
  ports?: string;
  created?: string;
}

export interface SystemDocker {
  available: boolean;
  version?: string;
  running: number;
  containers: SystemContainer[];
}

/** One active media session on the hub host, with the app that owns it. */
export interface SystemMedia {
  app: string;
  bundleID?: string;
  title?: string;
  artist?: string;
  album?: string;
  state?: "playing" | "paused" | "stopped";
  elapsedSeconds?: number;
  durationSeconds?: number;
  playbackRate?: number;
  /** Whether the session is known to be audio or video. */
  kind?: "audio" | "video";
  source?: "mediaremote" | "playerctl" | "applescript" | "assertion";
  /** MediaRemote command numbers the current player accepts. */
  supportedCommands?: number[];
}

/** System output volume, controllable from the Media card. */
export interface SystemAudio {
  volumePercent?: number;
  muted?: boolean;
  controllable: boolean;
}

export interface MediaControlResult {
  media: SystemMedia[];
  audio: SystemAudio | null;
}

export interface SystemInfoResponse {
  data: SystemInfo;
}

export interface MediaControlResponse {
  data: MediaControlResult;
}

// MARK: - Host file browser

export interface HostFileRoot {
  name: string;
  path: string;
  kind?: string;
}

export interface HostFileEntry {
  name: string;
  path: string;
  kind: "directory" | "file" | "symlink" | "other";
  isDirectory: boolean;
  size?: number;
  /** Milliseconds since the epoch. */
  modified?: number;
  permissions?: string;
  hidden: boolean;
  linkTarget?: string;
  error?: string;
}

export interface HostDirectory {
  path: string;
  name: string;
  parent: string | null;
  roots: HostFileRoot[];
  entries: HostFileEntry[];
  total: number;
  truncated: boolean;
}

export interface HostFileContent {
  path: string;
  name: string;
  size: number;
  modified: number;
  kind: "text" | "image" | "binary";
  mime: string;
  content?: string;
  truncated: boolean;
  maxBytes: number;
}

export interface HostRawFile {
  bytes: Uint8Array;
  mime: string;
  name: string;
  size: number;
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

/**
 * Virtual-machine management served by the hub.
 *
 * The hub owns the VM definitions on disk and drives a small Swift helper that
 * runs guests with Apple's Virtualization.framework. The first supported guest
 * is NixOS, built declaratively from a generated `configuration.nix`.
 */

export type VMStatus =
  | "building"
  | "stopped"
  | "starting"
  | "running"
  | "stopping"
  | "paused"
  | "error";

export type VMAction =
  | "start"
  | "stop"
  | "restart"
  | "pause"
  | "resume"
  | "rebuild"
  | "apply";

export interface VMProgress {
  /** Short machine-readable phase: queued, resolving, building, copying, starting, applying. */
  phase: string;
  message: string;
  /** Milliseconds since the epoch. */
  startedAt: number;
}

export interface VMHostMetrics {
  /** CPU percentage of the helper process, when known. */
  cpuPercent?: number;
  /** Resident set size of the helper process, in bytes. */
  rssBytes?: number;
  /** Logical size of the disk image, in bytes. */
  diskBytes?: number;
  /** Bytes actually allocated on the host. */
  diskUsedBytes?: number;
  /** Helper uptime in seconds. */
  uptimeSec?: number;
}

export interface VMGuestMetrics {
  reachable: boolean;
  /** Seconds since the guest booted. */
  uptimeSec?: number;
  cpuPercent?: number;
  load1?: number;
  load5?: number;
  load15?: number;
  memoryTotalBytes?: number;
  memoryUsedBytes?: number;
  memoryAvailableBytes?: number;
  swapUsedBytes?: number;
  diskTotalBytes?: number;
  diskUsedBytes?: number;
  diskAvailableBytes?: number;
  hostname?: string;
  kernel?: string;
  /** Current NixOS system store path, e.g. /nix/store/…-nixos-system-… */
  generation?: string;
  error?: string;
}

export interface VMMetrics {
  collectedAt: number;
  state?: string;
  host?: VMHostMetrics;
  guest?: VMGuestMetrics;
}

export interface VMSshInfo {
  user: string;
  /** Absolute path to the private key generated for this VM. */
  keyPath: string;
  /** OpenSSH public key, safe to show in the UI. */
  publicKey: string;
}

export interface VMNetworkInfo {
  mac: string;
  /** Address discovered from the host ARP table while the guest is running. */
  ip: string | null;
  /** Whether the guest accepts SSH on port 22. */
  reachable: boolean;
}

/** One additional login rendered into `users.users.<name>`. */
export interface NixOSManagedUser {
  /** Unix login name. `root` and `opencodebar` are reserved. */
  name: string;
  description: string;
  /** Additional groups joined to the user's primary group. */
  groups: string[];
  shell: "bash" | "zsh" | "fish";
  /** OpenSSH public keys authorized for this login. */
  sshKeys: string[];
  /** Add a NOPASSWD sudo rule for this user. */
  passwordlessSudo: boolean;
  createHome: boolean;
}

export interface NixOSBuilderSettings {
  timezone: string;
  locale: string;
  keymap: string;
  firewall: boolean;
  /** Permit password logins over SSH. Off by default; keys are required. */
  passwordAuthentication: boolean;
  /** Extra TCP/UDP ports opened on the guest firewall. */
  extraTCPPorts: number[];
  extraUDPPorts: number[];
}

/**
 * The declarative, click-together description of a guest. `enabled` holds
 * catalog option ids; everything else is the small set of values that cannot
 * be expressed as a boolean option.
 */
export interface NixOSBuilderConfig {
  version: 1;
  /** The preset the user applied last, kept for the UI. */
  preset: string | null;
  enabled: string[];
  settings: NixOSBuilderSettings;
  users: NixOSManagedUser[];
  extraPackages: string[];
  /** Raw Nix module body appended verbatim for advanced users. */
  extraConfig: string;
}

export type VMConfigCategoryID =
  | "system"
  | "desktop"
  | "development"
  | "containers"
  | "services"
  | "networking"
  | "media"
  | "ai"
  | "observability"
  | "security"
  | "gaming"
  | "advanced";

export interface VMConfigCategory {
  id: VMConfigCategoryID;
  name: string;
  summary: string;
  /** SF Symbol name understood by the macOS and iOS clients. */
  icon: string;
  /** Theme palette key: accent, input, output, reasoning, warn, danger, running. */
  tint: string;
}

export interface VMConfigOption {
  id: string;
  category: VMConfigCategoryID;
  name: string;
  summary: string;
  description: string;
  icon: string;
  tint: string;
  tags: string[];
  /** Short label shown on the card, for example "Popular" or "Self-hosted". */
  badge: string | null;
  /** nixpkgs attributes added to environment.systemPackages. */
  packages: string[];
  /** Options automatically enabled with this one. */
  requires: string[];
  /** Options worth suggesting but not enabling automatically. */
  recommends: string[];
  /** Options that cannot be enabled at the same time. */
  conflicts: string[];
  /** Informational port list; the Nix snippet opens the firewall itself. */
  ports: number[];
  /** Human-readable service names for the build plan. */
  services: string[];
  /** Enabled in a fresh configuration. */
  defaultOn: boolean;
  /** Always on and not toggleable. */
  locked: boolean;
  /** Rough installed size used by the build-plan estimate. */
  sizeMB: number;
  /** Requires `nixpkgs.config.allowUnfree`. */
  unfree: boolean;
}

export interface VMConfigPreset {
  id: string;
  name: string;
  summary: string;
  icon: string;
  tint: string;
  options: string[];
  tags: string[];
}

export interface VMConfigLimits {
  maxUsers: number;
  maxExtraPackages: number;
  maxExtraConfigBytes: number;
  maxPorts: number;
}

export interface VMConfigCatalog {
  version: 1;
  categories: VMConfigCategory[];
  options: VMConfigOption[];
  presets: VMConfigPreset[];
  defaults: NixOSBuilderConfig;
  recommendedPreset: string | null;
  shells: string[];
  groups: string[];
  timezones: string[];
  locales: string[];
  keymaps: string[];
  limits: VMConfigLimits;
}

export interface VMConfigPreview {
  configuration: string;
  flake: string;
  /** All package attributes in the rendered configuration, sorted. */
  packages: string[];
  services: string[];
  ports: number[];
  users: string[];
  /** Number of enabled catalog options, excluding locked core options. */
  optionCount: number;
  /** Options added automatically because another option requires them. */
  added: string[];
  warnings: string[];
  /** Rough installed-size estimate in MiB. */
  sizeMB: number;
  stateVersion: string;
}

export interface VMConfigPreviewInput {
  config?: unknown;
  packages?: unknown;
}

export interface VMPaths {
  directory: string;
  disk: string;
  configuration: string;
  flake: string;
  serialLog: string;
  buildLog: string;
  applyLog: string;
  /** Helper runtime record: pid and the loopback control/serial ports. */
  runtime: string;
}

export interface VirtualMachine {
  id: string;
  name: string;
  /** Only "nixos" for now; kept explicit so other distros can follow. */
  distro: "nixos";
  /** NixOS channel used for the image and guest rebuilds, e.g. nixos-26.05. */
  channel: string;
  /** NixOS stateVersion captured when the VM was created. */
  stateVersion: string;
  arch: string;
  status: VMStatus;
  /** Milliseconds since the epoch. */
  createdAt: number;
  updatedAt: number;
  cpuCount: number;
  memoryMB: number;
  diskGB: number;
  /** Packages currently active in the generated configuration. */
  packages: string[];
  /** Package changes waiting for the guest to become reachable. */
  pendingPackages: string[];
  /** True when the builder configuration changed but has not been applied. */
  pendingConfig: boolean;
  /** The click-together builder configuration. */
  config: NixOSBuilderConfig;
  lastError: string | null;
  progress: VMProgress | null;
  ssh: VMSshInfo;
  network: VMNetworkInfo;
  paths: VMPaths;
  /** Milliseconds since the epoch of the current/last boot. */
  startedAt?: number;
  lastBootAt?: number;
  metrics?: VMMetrics | null;
}

export interface VMCapabilities {
  supported: boolean;
  platform: string;
  arch: string;
  helperPath: string | null;
  helperAvailable: boolean;
  /** The helper is signed with com.apple.security.virtualization. */
  helperEntitled: boolean;
  nixPath: string | null;
  nixAvailable: boolean;
  nixVersion: string | null;
  /**
   * Whether Nix is configured with an aarch64-linux builder. Building a NixOS
   * image on Apple Silicon requires one (for example darwin.linux-builder).
   */
  linuxBuilder: boolean;
  linuxBuilderDetail: string | null;
  storageDir: string;
  defaultChannel: string;
  defaultCPU: number;
  defaultMemoryMB: number;
  maxCPU: number;
  maxMemoryMB: number;
  /** Human-readable setup or limitation notes, newest first. */
  notes: string[];
}

export interface VMCreateInput {
  name: string;
  cpuCount?: number;
  memoryMB?: number;
  diskGB?: number;
  channel?: string;
  packages?: string[];
  /** Full builder configuration. Replaces the package-derived defaults. */
  config?: unknown;
  /** Boot the VM as soon as the image is ready. Defaults to true. */
  autostart?: boolean;
}

export interface VMUpdateInput {
  name?: string;
  cpuCount?: number;
  memoryMB?: number;
  /** Replaces the package list. Applied when the guest is reachable. */
  packages?: string[];
  /** Replaces the builder configuration. */
  config?: unknown;
}

export type VMLogType = "build" | "serial" | "apply";

export interface VMLog {
  type: VMLogType;
  path: string;
  lines: string[];
  bytes: number;
  truncated: boolean;
}

/**
 * Stored setup-log categories. `builder` is a long-lived Nix build-service VM
 * started by the user; the app can read its captured console log but does not
 * start it as a setup job.
 */
export type VMSetupStep = "nix" | "helper" | "builder";

export type VMSetupJobStatus = "running" | "succeeded" | "failed" | "cancelled";

export interface VMSetupLog {
  path: string;
  lines: string[];
  bytes: number;
  truncated: boolean;
}

export interface VMSetupJob {
  step: VMSetupStep;
  status: VMSetupJobStatus;
  /** The command shown in the app. The hub always uses this fixed command. */
  command: string;
  /** True when macOS shows its administrator password prompt on the Mac. */
  requiresAdmin: boolean;
  startedAt: number;
  finishedAt: number | null;
  exitCode: number | null;
  error: string | null;
  log: VMSetupLog;
}

/** One stored installer/helper log, including rotated history. */
export interface VMSetupLogFile {
  step: VMSetupStep;
  path: string;
  bytes: number;
  /** Milliseconds since the epoch. */
  modified: number;
}

export interface VMSetupLogResult {
  step: VMSetupStep;
  path: string;
  lines: string[];
  bytes: number;
  truncated: boolean;
}

export interface VMConsoleTarget {
  vmID: string;
  /** The helper listens on loopback only. */
  host: string;
  port: number;
}

/**
 * The subset the HTTP layer needs. Tests inject a fake; production uses
 * `VirtualMachineService`.
 */
export interface VirtualMachineStore {
  list(): Promise<VirtualMachine[]>;
  capabilities(): Promise<VMCapabilities>;
  get(id: string, refresh?: boolean): Promise<VirtualMachine | null>;
  create(input: VMCreateInput): Promise<VirtualMachine>;
  control(id: string, action: VMAction, force?: boolean): Promise<VirtualMachine>;
  update(id: string, input: VMUpdateInput): Promise<VirtualMachine>;
  remove(id: string, force?: boolean): Promise<void>;
  log(id: string, type: VMLogType, tail?: number): Promise<VMLog>;
  consoleTarget(id: string): Promise<VMConsoleTarget>;
  setupStatus(): Promise<VMSetupJob | null>;
  startSetup(step: VMSetupStep): Promise<VMSetupJob>;
  cancelSetup(): Promise<VMSetupJob | null>;
  setupLogs(): Promise<VMSetupLogFile[]>;
  setupLog(step: VMSetupStep, tail?: number): Promise<VMSetupLogResult>;
}

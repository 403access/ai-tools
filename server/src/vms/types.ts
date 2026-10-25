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
  /** Boot the VM as soon as the image is ready. Defaults to true. */
  autostart?: boolean;
}

export interface VMUpdateInput {
  name?: string;
  cpuCount?: number;
  memoryMB?: number;
  /** Replaces the package list. Applied when the guest is reachable. */
  packages?: string[];
}

export type VMLogType = "build" | "serial" | "apply";

export interface VMLog {
  type: VMLogType;
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
}

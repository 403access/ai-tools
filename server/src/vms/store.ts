import { randomBytes } from "node:crypto";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { dataDir } from "../config.ts";
import type { VMPaths, VirtualMachine } from "./types.ts";

/** Environment override used by tests and by users who keep VMs elsewhere. */
export const VM_DIR_ENV = "OPENCODEBAR_VM_DIR";

const VM_ID = /^vm_[a-z0-9]{8,32}$/;

export function vmRoot(env: NodeJS.ProcessEnv = process.env): string {
  const override = env[VM_DIR_ENV]?.trim();
  return override ? resolve(override) : join(dataDir(env), "vms");
}

export function isVMID(value: string): boolean {
  return VM_ID.test(value);
}

export function newVMID(): string {
  return `vm_${randomBytes(6).toString("hex")}`;
}

/** RFC 1123 hostname derived from the opaque id, never from the display name. */
export function hostnameFor(id: string): string {
  return `ocb-${id.replace(/^vm_/, "").slice(0, 12)}`;
}

function hex(value: number): string {
  return value.toString(16).padStart(2, "0");
}

/** A locally administered unicast MAC that does not collide with another VM. */
export function newMACAddress(existing: VirtualMachine[] = []): string {
  const used = new Set(existing.map((vm) => vm.network.mac.toLowerCase()));
  for (let attempt = 0; attempt < 512; attempt += 1) {
    const bytes = randomBytes(3);
    const mac = `52:54:00:${hex(bytes[0]!)}:${hex(bytes[1]!)}:${hex(bytes[2]!)}`;
    if (!used.has(mac)) return mac;
  }
  throw new Error("Could not allocate a unique MAC address");
}

export function vmLayout(root: string, id: string): VMPaths {
  const directory = join(root, id);
  return {
    directory,
    disk: join(directory, "disk.raw"),
    configuration: join(directory, "configuration.nix"),
    flake: join(directory, "flake.nix"),
    serialLog: join(directory, "serial.log"),
    buildLog: join(directory, "build.log"),
    applyLog: join(directory, "apply.log"),
    runtime: join(directory, "runtime.json"),
  };
}

export interface VMStoreOptions {
  root?: string;
}

/**
 * Reads and writes one directory per VM under the hub's data directory.
 *
 * `vm.json` is the source of truth for a definition. Runtime information (the
 * helper pid, assigned address, metrics) is also persisted there so the list
 * still renders after a hub restart. Writes are atomic and owner-only.
 */
export class VMStore {
  readonly root: string;

  constructor(options: VMStoreOptions = {}) {
    this.root = resolve(options.root ?? vmRoot());
  }

  ensureRoot(): void {
    mkdirSync(this.root, { recursive: true, mode: 0o700 });
  }

  directory(id: string): string {
    if (!isVMID(id)) throw new Error("Invalid VM id");
    return join(this.root, id);
  }

  metaPath(id: string): string {
    return join(this.directory(id), "vm.json");
  }

  list(): VirtualMachine[] {
    this.ensureRoot();
    const entries: VirtualMachine[] = [];
    for (const name of readdirSync(this.root, { withFileTypes: true })) {
      if (!name.isDirectory() || !isVMID(name.name)) continue;
      const vm = this.read(name.name);
      if (vm) entries.push(vm);
    }
    entries.sort((a, b) => b.createdAt - a.createdAt);
    return entries;
  }

  read(id: string): VirtualMachine | null {
    if (!isVMID(id)) return null;
    try {
      const value: unknown = JSON.parse(readFileSync(this.metaPath(id), "utf8"));
      if (!value || typeof value !== "object" || Array.isArray(value)) return null;
      return normalize(value as Partial<VirtualMachine>, id, this.root);
    } catch {
      return null;
    }
  }

  createLayout(id: string): VMPaths {
    const paths = vmLayout(this.root, id);
    mkdirSync(paths.directory, { recursive: true, mode: 0o700 });
    mkdirSync(join(paths.directory, "ssh"), { recursive: true, mode: 0o700 });
    return paths;
  }

  write(vm: VirtualMachine): void {
    const directory = this.directory(vm.id);
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    const target = this.metaPath(vm.id);
    const temp = `${target}.tmp`;
    writeFileSync(temp, `${JSON.stringify(vm, null, 2)}\n`, { mode: 0o600 });
    chmodSync(temp, 0o600);
    renameSync(temp, target);
  }

  remove(id: string): void {
    rmSync(this.directory(id), { recursive: true, force: true });
  }

  /** Cheap existence check used by the service. */
  exists(id: string): boolean {
    return isVMID(id) && existsSync(this.metaPath(id));
  }
}

/** Fills in fields older definitions may be missing. */
function normalize(
  value: Partial<VirtualMachine>,
  id: string,
  root: string,
): VirtualMachine | null {
  if (typeof value.name !== "string" || !value.name.trim()) return null;
  if (value.distro !== "nixos") return null;

  const layout = vmLayout(root, id);
  const createdAt = numberOr(value.createdAt, Date.now());
  const packages = stringArray(value.packages);
  // Derive paths from the current root so moving the VM directory (or setting
  // OPENCODEBAR_VM_DIR) keeps working instead of reading stale absolute paths.
  const paths: VMPaths = layout;

  return {
    id,
    name: value.name.trim().slice(0, 80),
    distro: "nixos",
    channel: textOr(value.channel, "nixos-26.05"),
    stateVersion: textOr(value.stateVersion, "26.05"),
    arch: textOr(value.arch, "aarch64"),
    status: (value.status as VirtualMachine["status"]) ?? "stopped",
    createdAt,
    updatedAt: numberOr(value.updatedAt, createdAt),
    cpuCount: numberOr(value.cpuCount, 2),
    memoryMB: numberOr(value.memoryMB, 4096),
    diskGB: numberOr(value.diskGB, 20),
    packages,
    pendingPackages: stringArray(value.pendingPackages),
    lastError: typeof value.lastError === "string" ? value.lastError : null,
    progress: value.progress ?? null,
    ssh: {
      user: textOr(value.ssh?.user, "opencodebar"),
      keyPath: join(layout.directory, "ssh", "id_ed25519"),
      publicKey: textOr(value.ssh?.publicKey, ""),
    },
    network: {
      mac: textOr(value.network?.mac, "52:54:00:00:00:00"),
      ip: value.network?.ip ?? null,
      reachable: value.network?.reachable === true,
    },
    paths,
    startedAt: typeof value.startedAt === "number" ? value.startedAt : undefined,
    lastBootAt: typeof value.lastBootAt === "number" ? value.lastBootAt : undefined,
    metrics: value.metrics ?? null,
  };
}

function textOr(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function numberOr(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string" && entry.length > 0);
}

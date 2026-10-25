import { existsSync, mkdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import type { CommandResult, CommandRunner } from "../system/types.ts";
import { defaultRunner } from "../system/commands.ts";
import { readRuntime } from "./helper.ts";
import { readLogTail } from "./logs.ts";
import type {
  VMGuestMetrics,
  VMHostMetrics,
  VMMetrics,
  VirtualMachine,
} from "./types.ts";

const SSH_TIMEOUT_MS = 8_000;

export function sshKeyDirectory(vm: VirtualMachine): string {
  return dirname(vm.ssh.keyPath);
}

export function knownHostsPath(vm: VirtualMachine): string {
  return join(sshKeyDirectory(vm), "known_hosts");
}

export function sshArguments(vm: VirtualMachine, timeoutSec = 4): string[] {
  const directory = sshKeyDirectory(vm);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  return [
    "ssh",
    "-i",
    vm.ssh.keyPath,
    "-p",
    "22",
    "-o",
    "BatchMode=yes",
    "-o",
    `ConnectTimeout=${Math.max(1, Math.round(timeoutSec))}`,
    "-o",
    "StrictHostKeyChecking=accept-new",
    "-o",
    `UserKnownHostsFile=${knownHostsPath(vm)}`,
    "-o",
    "LogLevel=ERROR",
    "-o",
    "ServerAliveInterval=5",
    "-o",
    "ServerAliveCountMax=1",
  ];
}

export function scpArguments(vm: VirtualMachine): string[] {
  return [
    "scp",
    "-i",
    vm.ssh.keyPath,
    "-P",
    "22",
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=4",
    "-o",
    "StrictHostKeyChecking=accept-new",
    "-o",
    `UserKnownHostsFile=${knownHostsPath(vm)}`,
    "-o",
    "LogLevel=ERROR",
  ];
}

export function guestTarget(vm: VirtualMachine): string | null {
  if (!vm.network.ip) return null;
  return `${vm.ssh.user}@${vm.network.ip}`;
}

export async function runGuest(
  vm: VirtualMachine,
  command: string,
  runner: CommandRunner = defaultRunner,
  timeoutMs = SSH_TIMEOUT_MS,
): Promise<CommandResult> {
  const target = guestTarget(vm);
  if (!target) {
    return { ok: false, stdout: "", stderr: "The guest does not have an address yet" };
  }
  return runner(
    "ssh",
    [...sshArguments(vm), target, command],
    timeoutMs,
  );
}

export async function waitForGuestSSH(
  vm: VirtualMachine,
  runner: CommandRunner = defaultRunner,
  timeoutMs = 90_000,
): Promise<boolean> {
  const target = guestTarget(vm);
  if (!target) return false;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const result = await runGuest(vm, "true", runner, 5_000);
    if (result.ok) return true;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  return false;
}

/** Copies local files into a temporary directory on the guest. */
export async function scpToGuest(
  vm: VirtualMachine,
  files: string[],
  remoteDirectory: string,
  runner: CommandRunner = defaultRunner,
  timeoutMs = 20_000,
): Promise<CommandResult> {
  const target = guestTarget(vm);
  if (!target) {
    return { ok: false, stdout: "", stderr: "The guest does not have an address yet" };
  }
  const mkdir = `mkdir -p ${shellQuote(remoteDirectory)}`;
  const prepared = await runGuest(vm, mkdir, runner, timeoutMs);
  if (!prepared.ok) return prepared;
  return runner(
    "scp",
    [...scpArguments(vm), ...files, `${target}:${remoteDirectory}/`],
    timeoutMs,
  );
}

export function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function normalizeMAC(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .split(":")
    .map((part) => Number.parseInt(part, 16).toString(16))
    .join(":");
}

/** Finds the guest's DHCP address from the host ARP table. */
export async function findGuestAddress(
  vm: VirtualMachine,
  runner: CommandRunner = defaultRunner,
): Promise<string | null> {
  if (process.platform !== "darwin") return null;
  const mac = normalizeMAC(vm.network.mac);
  // `/usr/sbin` is missing from some GUI-launched PATHs.
  const result = await runner("/usr/sbin/arp", ["-an"], 5_000);
  if (result.ok) {
    for (const line of result.stdout.split(/\r?\n/)) {
      const address = /\(([^)]+)\)/.exec(line)?.[1];
      const seen = /\sat\s+([0-9a-f:]+)/i.exec(line)?.[1];
      if (address && seen && normalizeMAC(seen) === mac) return address;
    }
  }

  // During early boot the ARP entry may not be there yet, but the guest logs
  // the address it received. This also works for a guest on a bridge.
  const tail = readLogTail(vm.paths.serialLog, 400, 256 * 1024);
  for (let index = tail.lines.length - 1; index >= 0; index -= 1) {
    const line = tail.lines[index] ?? "";
    const match = /(?:DHCPv4 address|inet)\s+(192\.168\.\d{1,3}\.\d{1,3})/.exec(line);
    if (match?.[1]) return match[1];
  }
  return null;
}

/** Host-side facts that do not require the guest to be reachable. */
export function hostMetrics(vm: VirtualMachine, runner: CommandRunner = defaultRunner): Promise<VMHostMetrics> {
  return (async () => {
    const metrics: VMHostMetrics = {};
    const runtime = readRuntime(join(vm.paths.directory, "runtime.json"));
    if (runtime) {
      metrics.uptimeSec = Math.max(0, Math.round((Date.now() - runtime.startedAt) / 1_000));
      const ps = await runner(
        "ps",
        ["-o", "%cpu=", "-o", "rss=", "-p", String(runtime.pid)],
        4_000,
      );
      if (ps.ok) {
        const [cpu, rss] = ps.stdout.trim().split(/\s+/);
        const cpuValue = Number(cpu);
        const rssKB = Number(rss);
        if (Number.isFinite(cpuValue)) metrics.cpuPercent = Math.round(cpuValue * 10) / 10;
        if (Number.isFinite(rssKB)) metrics.rssBytes = rssKB * 1024;
      }
    }
    try {
      const stats = statSync(vm.paths.disk);
      metrics.diskBytes = stats.size;
      // APFS reports allocated blocks in 512-byte units.
      metrics.diskUsedBytes = Math.max(0, Number(stats.blocks) * 512);
    } catch {
      // The image has not been built yet.
    }
    return metrics;
  })();
}

interface CPUSample {
  total: number;
  idle: number;
}

const previousCPU = new Map<string, CPUSample>();

function parseCPU(line: string, previous: CPUSample | undefined): {
  percent?: number;
  sample?: CPUSample;
} {
  const parts = line.trim().split(/\s+/).slice(1).map(Number);
  if (parts.length < 4 || parts.some((value) => !Number.isFinite(value))) return {};
  const total = parts.reduce((sum, value) => sum + value, 0);
  const idle = (parts[3] ?? 0) + (parts[4] ?? 0);
  if (!previous) return { sample: { total, idle } };
  const totalDelta = total - previous.total;
  const idleDelta = idle - previous.idle;
  if (totalDelta <= 0) return { sample: { total, idle } };
  return {
    percent: Math.round(Math.min(100, Math.max(0, ((totalDelta - idleDelta) / totalDelta) * 100)) * 10) / 10,
    sample: { total, idle },
  };
}

function section(output: string, name: string): string {
  const marker = `##${name}`;
  const lines = output.split(/\r?\n/);
  const index = lines.findIndex((line) => line.trim() === marker);
  if (index < 0) return "";
  const values: string[] = [];
  for (let cursor = index + 1; cursor < lines.length; cursor += 1) {
    const line = lines[cursor] ?? "";
    if (line.startsWith("##")) break;
    values.push(line);
  }
  return values.join("\n").trim();
}

function numberValue(value: string | undefined): number | undefined {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

const PROBE_SCRIPT = [
  "printf '##uptime\\n'; cat /proc/uptime 2>/dev/null",
  "printf '##load\\n'; cat /proc/loadavg 2>/dev/null",
  "printf '##mem\\n'; grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null",
  "printf '##cpu\\n'; head -n 1 /proc/stat 2>/dev/null",
  "printf '##disk\\n'; df -B1 / 2>/dev/null | tail -n 1",
  "printf '##generation\\n'; readlink -f /run/current-system 2>/dev/null",
  "printf '##hostname\\n'; hostname 2>/dev/null",
  "printf '##kernel\\n'; uname -r 2>/dev/null",
].join("; ");

export async function guestMetrics(
  vm: VirtualMachine,
  runner: CommandRunner = defaultRunner,
): Promise<VMGuestMetrics> {
  if (!vm.network.ip) return { reachable: false, error: "Waiting for a guest address" };
  const result = await runGuest(vm, PROBE_SCRIPT, runner, SSH_TIMEOUT_MS);
  if (!result.ok) {
    return {
      reachable: false,
      error: result.stderr.trim().split(/\r?\n/).pop() ?? "SSH is not reachable",
    };
  }

  const guest: VMGuestMetrics = { reachable: true };
  const uptime = numberValue(section(result.stdout, "uptime").split(/\s+/)[0]);
  if (uptime !== undefined) guest.uptimeSec = Math.round(uptime);

  const load = section(result.stdout, "load").split(/\s+/).map(Number);
  if (load.length >= 3 && load.every((value) => Number.isFinite(value))) {
    guest.load1 = load[0];
    guest.load5 = load[1];
    guest.load15 = load[2];
  }

  for (const line of section(result.stdout, "mem").split(/\r?\n/)) {
    const [key, value] = line.split(":");
    const bytes = numberValue(value?.trim().split(/\s+/)[0]) ?? 0;
    if (!key || bytes <= 0) continue;
    if (key === "MemTotal") guest.memoryTotalBytes = bytes * 1024;
    if (key === "MemAvailable") guest.memoryAvailableBytes = bytes * 1024;
    if (key === "SwapTotal") guest.swapUsedBytes = bytes * 1024;
    if (key === "SwapFree") guest.swapUsedBytes = (guest.swapUsedBytes ?? 0) - bytes * 1024;
  }
  if (guest.memoryTotalBytes !== undefined && guest.memoryAvailableBytes !== undefined) {
    guest.memoryUsedBytes = Math.max(0, guest.memoryTotalBytes - guest.memoryAvailableBytes);
  }
  if (guest.swapUsedBytes !== undefined) {
    guest.swapUsedBytes = Math.max(0, guest.swapUsedBytes);
  }

  const cpuLine = section(result.stdout, "cpu");
  if (cpuLine) {
    const sample = parseCPU(cpuLine, previousCPU.get(vm.id));
    if (sample.sample) previousCPU.set(vm.id, sample.sample);
    if (sample.percent !== undefined) guest.cpuPercent = sample.percent;
  }

  const disk = section(result.stdout, "disk").trim().split(/\s+/);
  // Filesystem 1B-blocks Used Available Use% Mounted-on
  if (disk.length >= 4) {
    const total = Number(disk[1]);
    const used = Number(disk[2]);
    const available = Number(disk[3]);
    if (Number.isFinite(total)) guest.diskTotalBytes = total;
    if (Number.isFinite(used)) guest.diskUsedBytes = used;
    if (Number.isFinite(available)) guest.diskAvailableBytes = available;
  }

  const generation = section(result.stdout, "generation");
  if (generation) guest.generation = generation;
  const hostname = section(result.stdout, "hostname");
  if (hostname) guest.hostname = hostname;
  const kernel = section(result.stdout, "kernel");
  if (kernel) guest.kernel = kernel;
  return guest;
}

export async function collectMetrics(
  vm: VirtualMachine,
  runner: CommandRunner = defaultRunner,
): Promise<VMMetrics> {
  const [host, guest] = await Promise.all([
    hostMetrics(vm, runner),
    vm.status === "running" || vm.status === "paused"
      ? guestMetrics(vm, runner)
      : Promise.resolve<VMGuestMetrics>({ reachable: false }),
  ]);
  if (!existsSync(vm.paths.disk)) {
    host.diskBytes = 0;
    host.diskUsedBytes = 0;
  }
  return {
    collectedAt: Date.now(),
    state: vm.status,
    host,
    guest,
  };
}

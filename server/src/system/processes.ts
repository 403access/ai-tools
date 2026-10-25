import { platform } from "node:os";
import { basename } from "node:path";
import type { SystemProcess } from "../types.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { asRecord, numberValue, parseJSONValue, round, stringValue, text } from "./util.ts";

// The System snapshot is polled every few seconds, so only the most useful
// rows travel over the wire. Memory gets a longer list because the memory
// monitor opened from the overview tile behaves like a small Activity Monitor
// and folds helper processes into app groups client-side.
const TOP_CPU_LIMIT = 12;
const TOP_MEMORY_LIMIT = 100;

interface ProcessSummary {
  total: number;
  topCPU: SystemProcess[];
  topMemory: SystemProcess[];
}

export async function collectProcesses(run: CommandRunner): Promise<ProcessSummary> {
  const os = platform();
  if (os === "win32") {
    const result = await run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-Process | Select-Object Id,ProcessName,CPU,WorkingSet64,VirtualMemorySize64,Path | ConvertTo-Json -Compress",
      ],
      COMMAND_TIMEOUT_MS,
    );
    const raw = parseJSONValue(text(result));
    const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
    const processes: SystemProcess[] = entries.flatMap((rawEntry) => {
      const entry = asRecord(rawEntry);
      const pid = numberValue(entry?.Id);
      const name = stringValue(entry?.ProcessName);
      if (pid === undefined || !name) return [];
      return [{
        pid,
        name,
        command: stringValue(entry?.Path),
        memoryBytes: numberValue(entry?.WorkingSet64),
        virtualMemoryBytes: numberValue(entry?.VirtualMemorySize64),
      }];
    });
    return {
      total: processes.length,
      topCPU: processes.slice(0, TOP_CPU_LIMIT),
      topMemory: [...processes]
        .sort((a, b) => (b.memoryBytes ?? 0) - (a.memoryBytes ?? 0))
        .slice(0, TOP_MEMORY_LIMIT),
    };
  }

  const result = await run(
    "ps",
    ["-axo", "pid=,ppid=,pcpu=,pmem=,rss=,vsz=,etime=,state=,user=,comm="],
    COMMAND_TIMEOUT_MS,
  );
  if (!result.ok) return { total: 0, topCPU: [], topMemory: [] };
  return summarizeProcesses(text(result));
}

/**
 * Parses the fixed-width `ps` row emitted by `collectProcesses`. The command
 * comes last because executable paths on macOS commonly contain spaces.
 */
export function summarizeProcesses(value: string): ProcessSummary {
  const processes: SystemProcess[] = [];
  for (const line of value.split(/\r?\n/)) {
    const match = line.match(
      /^\s*(\d+)\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+)$/,
    );
    if (!match) continue;
    const pid = Number.parseInt(match[1] ?? "", 10);
    const parentPID = Number.parseInt(match[2] ?? "", 10);
    const cpu = Number.parseFloat(match[3] ?? "");
    const memoryPercent = Number.parseFloat(match[4] ?? "");
    const rss = Number.parseInt(match[5] ?? "", 10);
    const vsz = Number.parseInt(match[6] ?? "", 10);
    const elapsed = parseElapsedSeconds(match[7] ?? "");
    const state = match[8];
    const user = match[9];
    const command = (match[10] ?? "").trim();
    if (!Number.isFinite(pid) || !command) continue;
    processes.push({
      pid,
      parentPID: Number.isFinite(parentPID) ? parentPID : undefined,
      name: basename(command) || command,
      command,
      user,
      state,
      cpuPercent: Number.isFinite(cpu) ? round(cpu, 1) : undefined,
      memoryPercent: Number.isFinite(memoryPercent) ? round(memoryPercent, 1) : undefined,
      memoryBytes: Number.isFinite(rss) ? rss * 1_024 : undefined,
      virtualMemoryBytes: Number.isFinite(vsz) ? vsz * 1_024 : undefined,
      elapsedSeconds: elapsed,
    });
  }

  const topCPU = [...processes]
    .sort((a, b) => (b.cpuPercent ?? 0) - (a.cpuPercent ?? 0))
    .slice(0, TOP_CPU_LIMIT);
  const topMemory = [...processes]
    .sort((a, b) => (b.memoryBytes ?? 0) - (a.memoryBytes ?? 0))
    .slice(0, TOP_MEMORY_LIMIT);

  return { total: processes.length, topCPU, topMemory };
}

/**
 * `ps` prints elapsed time as `[[dd-]hh:]mm:ss`. Returns whole seconds so
 * clients do not have to understand the platform's formatting.
 */
export function parseElapsedSeconds(value: string): number | undefined {
  if (!value) return undefined;
  const [dayPart, clockPart] = value.includes("-") ? value.split("-", 2) : [undefined, value];
  const days = dayPart === undefined ? 0 : Number.parseInt(dayPart, 10);
  const parts = (clockPart ?? "").split(":").map((part) => Number.parseInt(part, 10));
  if (!Number.isFinite(days) || parts.some((part) => !Number.isFinite(part))) return undefined;

  let hours = 0;
  let minutes = 0;
  let seconds = 0;
  if (parts.length === 3) {
    [hours, minutes, seconds] = parts as [number, number, number];
  } else if (parts.length === 2) {
    [minutes, seconds] = parts as [number, number];
  } else if (parts.length === 1) {
    seconds = parts[0] ?? 0;
  } else {
    return undefined;
  }
  return days * 86_400 + hours * 3_600 + minutes * 60 + seconds;
}

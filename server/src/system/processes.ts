import { platform } from "node:os";
import { basename } from "node:path";
import type { SystemProcess } from "../types.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { asRecord, numberValue, parseJSONValue, round, stringValue, text } from "./util.ts";

export async function collectProcesses(run: CommandRunner): Promise<{ total: number; topCPU: SystemProcess[]; topMemory: SystemProcess[] }> {
  const os = platform();
  if (os === "win32") {
    const result = await run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-Process | Select-Object Id,ProcessName,CPU,WorkingSet64 | ConvertTo-Json -Compress",
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
        memoryBytes: numberValue(entry?.WorkingSet64),
      }];
    });
    return {
      total: processes.length,
      topCPU: processes.slice(0, 12),
      topMemory: [...processes]
        .sort((a, b) => (b.memoryBytes ?? 0) - (a.memoryBytes ?? 0))
        .slice(0, 12),
    };
  }

  const result = await run(
    "ps",
    ["-axo", "pid=,pcpu=,pmem=,rss=,user=,comm="],
    COMMAND_TIMEOUT_MS,
  );
  if (!result.ok) return { total: 0, topCPU: [], topMemory: [] };
  return summarizeProcesses(text(result));
}

export function summarizeProcesses(value: string): {
  total: number;
  topCPU: SystemProcess[];
  topMemory: SystemProcess[];
} {
  const processes: SystemProcess[] = [];
  for (const line of value.split(/\r?\n/)) {
    const match = line.match(/^\s*(\d+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(.+)$/);
    if (!match) continue;
    const pid = Number.parseInt(match[1] ?? "", 10);
    const cpu = Number.parseFloat(match[2] ?? "");
    const memoryPercent = Number.parseFloat(match[3] ?? "");
    const rss = Number.parseInt(match[4] ?? "", 10);
    const user = match[5];
    const command = (match[6] ?? "").trim();
    if (!Number.isFinite(pid) || !command) continue;
    processes.push({
      pid,
      name: basename(command) || command,
      command,
      user,
      cpuPercent: Number.isFinite(cpu) ? round(cpu, 1) : undefined,
      memoryPercent: Number.isFinite(memoryPercent) ? round(memoryPercent, 1) : undefined,
      memoryBytes: Number.isFinite(rss) ? rss * 1_024 : undefined,
    });
  }

  const topCPU = [...processes]
    .sort((a, b) => (b.cpuPercent ?? 0) - (a.cpuPercent ?? 0))
    .slice(0, 12);
  const topMemory = [...processes]
    .sort((a, b) => (b.memoryBytes ?? 0) - (a.memoryBytes ?? 0))
    .slice(0, 12);

  return { total: processes.length, topCPU, topMemory };
}

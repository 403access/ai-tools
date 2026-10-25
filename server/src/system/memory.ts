import { freemem, totalmem } from "node:os";
import type { SystemMemory } from "../types.ts";
import { lines } from "./util.ts";

export function collectMemory(staticMemory: Partial<SystemMemory>): SystemMemory {
  const total = totalmem();
  const free = freemem();
  // "Available" accounts for reclaimable cache/pages; using raw free makes
  // macOS look like it is out of memory (it keeps very little truly free).
  const available = staticMemory.availableBytes ?? free;
  return {
    totalBytes: total,
    freeBytes: free,
    usedBytes: Math.max(0, total - available),
    ...staticMemory,
  };
}

export function parseMemInfo(value: string): Partial<SystemMemory> {
  const fields: Record<string, number> = {};
  for (const line of lines(value)) {
    const match = line.match(/^(\S+):\s+(\d+)\s*kB/i);
    if (!match?.[1] || !match[2]) continue;
    fields[match[1]] = Number.parseInt(match[2], 10) * 1_024;
  }
  return {
    availableBytes: fields.MemAvailable,
    activeBytes: fields.Active,
    inactiveBytes: fields.Inactive,
    wiredBytes: fields.Unevictable ?? fields.Wired,
    cachedBytes: fields.Cached,
    compressedBytes: fields.SReclaimable,
    swapTotalBytes: fields.SwapTotal,
    swapFreeBytes: fields.SwapFree,
    swapUsedBytes: fields.SwapTotal !== undefined && fields.SwapFree !== undefined
      ? fields.SwapTotal - fields.SwapFree
      : undefined,
  };
}

export function parseVMStat(value: string): Partial<SystemMemory> {
  const pageSize = Number.parseInt(/page size of (\d+) bytes/.exec(value)?.[1] ?? "", 10);
  if (!Number.isFinite(pageSize)) return {};
  const pages: Record<string, number> = {};
  for (const line of lines(value)) {
    const match = line.match(/^([^:]+):\s+(\d+)\.?$/);
    if (!match?.[1] || !match[2]) continue;
    pages[match[1].trim()] = Number.parseInt(match[2], 10);
  }
  const bytes = (key: string): number | undefined => {
    const count = pages[key];
    return count === undefined ? undefined : count * pageSize;
  };
  return {
    freeBytes: bytes("Pages free"),
    activeBytes: bytes("Pages active"),
    inactiveBytes: bytes("Pages inactive"),
    wiredBytes: bytes("Pages wired down"),
    compressedBytes: bytes("Pages occupied by compressor"),
    cachedBytes: bytes("Pages purgeable"),
    availableBytes: (bytes("Pages free") ?? 0) + (bytes("Pages inactive") ?? 0),
  };
}

export function parseSwapUsage(value: string): { total?: number; used?: number; free?: number } {
  const match = value.match(/total\s*=\s*([\d.]+)([MG])\s+used\s*=\s*([\d.]+)([MG])\s+free\s*=\s*([\d.]+)([MG])/i);
  if (!match) return {};
  const size = (amount: string | undefined, unit: string | undefined): number | undefined => {
    const parsed = Number.parseFloat(amount ?? "");
    if (!Number.isFinite(parsed)) return undefined;
    return parsed * (unit?.toUpperCase() === "G" ? 1_073_741_824 : 1_048_576);
  };
  const total = size(match[1], match[2]);
  const used = size(match[3], match[4]);
  const free = size(match[5], match[6]);
  return {
    total: total === undefined ? undefined : Math.round(total),
    used: used === undefined ? undefined : Math.round(used),
    free: free === undefined ? undefined : Math.round(free),
  };
}

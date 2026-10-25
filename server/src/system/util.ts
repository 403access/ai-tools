import { readFileSync, readdirSync, statSync } from "node:fs";
import { cpus, platform, type, userInfo } from "node:os";
import type { CommandResult } from "./types.ts";

export function platformName(): string {
  switch (platform()) {
    case "darwin": return "macOS";
    case "linux": return "Linux";
    case "win32": return "Windows";
    default: return type();
  }
}

export function text(result: CommandResult | null): string {
  if (!result) return "";
  return result.stdout || result.stderr;
}

export function firstLine(value: string): string | undefined {
  const line = value.split(/\r?\n/).map((entry) => entry.trim()).find(Boolean);
  return line || undefined;
}

export function lines(value: string): string[] {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

export function unique(values: string[]): string[] {
  return [...new Set(values.filter(Boolean))];
}

export function round(value: number, decimals = 1): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

export function numberValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

export function stringValue(value: unknown): string | undefined {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return undefined;
}

export function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
}

export function parseJSON(value: string): Record<string, unknown> | null {
  const trimmed = value.trim();
  if (!trimmed.startsWith("{")) return null;
  try {
    return asRecord(JSON.parse(trimmed));
  } catch {
    return null;
  }
}

export function parseJSONRecord(value: string | undefined): Record<string, unknown> | null {
  if (!value) return null;
  try {
    return asRecord(JSON.parse(value));
  } catch {
    return null;
  }
}

export function firstObject(value: unknown): Record<string, unknown> | null {
  if (!Array.isArray(value)) return null;
  return asRecord(value[0]);
}

export function parseKeyValueLines(value: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of lines(value)) {
    const index = line.indexOf(":");
    if (index <= 0) continue;
    result[line.slice(0, index).trim()] = line.slice(index + 1).trim();
  }
  return result;
}

export function parseJSONValue(value: string): unknown {
  try {
    return JSON.parse(value.trim());
  } catch {
    return null;
  }
}

export function readFileSafe(path: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch {
    try {
      return readFileSync(path, "latin1");
    } catch {
      return "";
    }
  }
}

export function listDirectory(path: string): string[] {
  try {
    return readdirSync(path).filter((entry) => !entry.startsWith("."));
  } catch {
    return [];
  }
}

export function safeUsername(): string | undefined {
  try {
    return userInfo().username;
  } catch {
    return undefined;
  }
}

export function safeCwd(): string | undefined {
  try {
    return process.cwd();
  } catch {
    return undefined;
  }
}

export function fileSize(path: string | undefined): number | undefined {
  if (!path) return undefined;
  try {
    return statSync(path).size;
  } catch {
    return undefined;
  }
}

export function cpuModel(): string | undefined {
  return cpus()[0]?.model;
}


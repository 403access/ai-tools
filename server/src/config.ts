import { randomBytes } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, networkInterfaces } from "node:os";
import { dirname, join } from "node:path";

export const HUB_VERSION = "1.0.0";
export const DEFAULT_PORT = 8787;

/** Coalescing window for event-stream updates sent to the apps. */
export const DEFAULT_EVENT_THROTTLE_MS = 250;
export const MIN_EVENT_THROTTLE_MS = 0;
export const MAX_EVENT_THROTTLE_MS = 5_000;

export function clampEventThrottle(value: number): number {
  if (!Number.isFinite(value)) return DEFAULT_EVENT_THROTTLE_MS;
  return Math.min(Math.max(Math.round(value), MIN_EVENT_THROTTLE_MS), MAX_EVENT_THROTTLE_MS);
}

export interface HubConfig {
  host: string;
  port: number;
  token: string;
  dbPath: string;
  configPath: string;
  opencodeURL?: string;
  opencodePassword?: string;
  goUsageURL: string;
  goUsageKey?: string;
  fastPollMs: number;
  slowPollMs: number;
  usagePollMs: number;
  /**
   * Coalesces event-stream updates for this many milliseconds before sending
   * them to the apps. `0` forwards every event immediately.
   */
  eventThrottleMs: number;
  logLevel: "debug" | "info" | "warn";
}

function home(): string {
  return homedir();
}

export function configDir(env: NodeJS.ProcessEnv = process.env): string {
  const xdg = env.XDG_CONFIG_HOME?.trim();
  return xdg ? join(xdg, "opencode") : join(home(), ".config", "opencode");
}

export function dataDir(env: NodeJS.ProcessEnv = process.env): string {
  const xdg = env.XDG_DATA_HOME?.trim();
  return xdg ? join(xdg, "opencodebar") : join(home(), ".local", "share", "opencodebar");
}

export function opencodeDataDir(env: NodeJS.ProcessEnv = process.env): string {
  const xdg = env.XDG_DATA_HOME?.trim();
  return xdg ? join(xdg, "opencode") : join(home(), ".local", "share", "opencode");
}

function readJSON(path: string): Record<string, unknown> | null {
  try {
    if (!existsSync(path)) return null;
    const value = JSON.parse(readFileSync(path, "utf8"));
    return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function str(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function num(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() && Number.isFinite(Number(value))) return Number(value);
  return undefined;
}

/**
 * Resolves the Go usage key in the same order as the original macOS app:
 * environment, the app's own config, then OpenCode's auth store.
 */
export function resolveGoUsageKey(env: NodeJS.ProcessEnv = process.env): string | undefined {
  for (const name of ["OPENCODE_GO_USAGE_KEY", "OPENCODE_API_KEY"]) {
    const value = env[name]?.trim();
    if (value) return value;
  }

  const appConfig = readJSON(join(configDir(env), "opencodebar.json"));
  const appKey = str(appConfig?.goUsageKey);
  if (appKey) return appKey;

  const auth = readJSON(join(opencodeDataDir(env), "auth.json"));
  for (const provider of ["opencode-go", "opencode"]) {
    const entry = auth?.[provider];
    if (entry && typeof entry === "object") {
      const key = str((entry as Record<string, unknown>).key);
      if (key) return key;
    }
  }
  return undefined;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): HubConfig {
  const configPath = join(configDir(env), "opencodebar-hub.json");
  const saved = readJSON(configPath);

  const token =
    str(env.OPENCODEBAR_HUB_TOKEN) ??
    str(saved?.token) ??
    randomBytes(24).toString("base64url");

  const port =
    num(env.OPENCODEBAR_HUB_PORT) ??
    num(saved?.port) ??
    DEFAULT_PORT;

  const dbPath =
    str(env.OPENCODEBAR_HUB_DB) ??
    join(dataDir(env), "hub.sqlite");

  const opencodeURL =
    str(env.OPENCODEBAR_OPENCODE_URL) ??
    str(env.OPENCODE_SERVICE_URL);

  const opencodePassword =
    str(env.OPENCODE_SERVICE_PASSWORD) ??
    str(readJSON(join(configDir(env), "service.json"))?.password);

  return {
    host: str(env.OPENCODEBAR_HUB_HOST) ?? "0.0.0.0",
    port,
    token,
    dbPath,
    configPath,
    opencodeURL,
    opencodePassword,
    goUsageURL:
      str(env.OPENCODE_GO_USAGE_URL) ??
      "https://opencode.ai/zen/go/v1/usage",
    goUsageKey: resolveGoUsageKey(env),
    fastPollMs: num(env.OPENCODEBAR_FAST_POLL_MS) ?? 5_000,
    slowPollMs: num(env.OPENCODEBAR_SLOW_POLL_MS) ?? 60_000,
    usagePollMs: num(env.OPENCODEBAR_USAGE_POLL_MS) ?? 60_000,
    eventThrottleMs: clampEventThrottle(
      num(env.OPENCODEBAR_EVENT_THROTTLE_MS) ??
        num(saved?.eventThrottleMs) ??
        DEFAULT_EVENT_THROTTLE_MS,
    ),
    logLevel: (str(env.OPENCODEBAR_LOG_LEVEL) as HubConfig["logLevel"]) ?? "info",
  };
}

/**
 * Writes the connection details the native clients read. The token is sensitive,
 * so the file is created owner-only.
 */
export function writeHubConfig(config: HubConfig, port = config.port): void {
  mkdirSync(dirname(config.configPath), { recursive: true, mode: 0o700 });
  const payload = {
    url: `http://127.0.0.1:${port}`,
    token: config.token,
    port,
    version: HUB_VERSION,
    eventThrottleMs: config.eventThrottleMs,
    updatedAt: new Date().toISOString(),
  };
  writeFileSync(config.configPath, JSON.stringify(payload, null, 2) + "\n", {
    encoding: "utf8",
    mode: 0o600,
  });
  try {
    chmodSync(config.configPath, 0o600);
  } catch {
    // Best effort on filesystems that do not support chmod.
  }
}

export interface LanAddress {
  interface: string;
  address: string;
  url: string;
}

export function lanAddresses(port: number): LanAddress[] {
  const result: LanAddress[] = [];
  for (const [name, addresses] of Object.entries(networkInterfaces())) {
    for (const address of addresses ?? []) {
      if (address.family !== "IPv4" || address.internal) continue;
      // 169.254/16 is self-assigned link-local (it also shows up on inactive
      // interfaces) and a phone cannot use it.
      if (address.address.startsWith("169.254.")) continue;
      result.push({
        interface: name,
        address: address.address,
        url: `http://${address.address}:${port}`,
      });
    }
  }
  return result;
}

export function pairingLink(url: string, token: string): string {
  return `opencodebar://pair?url=${encodeURIComponent(url)}&token=${encodeURIComponent(token)}`;
}

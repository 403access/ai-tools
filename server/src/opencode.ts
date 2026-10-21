import { existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { configDir, opencodeDataDir, type HubConfig } from "./config.ts";
import type {
  ActiveSessionsResponse,
  GoUsage,
  HubEvent,
  MessagesResponse,
  Project,
  ServerInfo,
  Session,
  SessionsResponse,
  StatsResponse,
} from "./types.ts";

export interface OpenCodeLocation {
  url: string;
  password: string;
}

export class OpenCodeError extends Error {
  readonly status?: number;

  constructor(message: string, status?: number) {
    super(message);
    this.name = "OpenCodeError";
    this.status = status;
  }

  get unauthorized(): boolean {
    return this.status === 401 || this.status === 403;
  }
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

function envString(env: NodeJS.ProcessEnv, name: string): string | undefined {
  const value = env[name]?.trim();
  return value ? value : undefined;
}

async function runCommand(command: string[], timeoutMs: number): Promise<string | null> {
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn(command, {
      stdout: "pipe",
      stderr: "pipe",
      stdin: "ignore",
    });
  } catch {
    return null;
  }

  const read = (async () => {
    const output = await new Response(proc.stdout as ReadableStream).text();
    const code = await proc.exited;
    return code === 0 ? output : null;
  })();

  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<null>((resolve) => {
    timer = setTimeout(() => {
      try {
        proc.kill();
      } catch {
        // Already gone.
      }
      resolve(null);
    }, timeoutMs);
  });

  try {
    return await Promise.race([read, timeout]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function firstURL(text: string, requireLoopback = false): string | null {
  const matches = text.match(/https?:\/\/[A-Za-z0-9._-]+:[0-9]+/g) ?? [];
  let fallback: string | null = null;
  for (const candidate of matches.reverse()) {
    const loopback = candidate.includes("127.0.0.1") || candidate.includes("localhost");
    if (loopback) return candidate;
    if (!requireLoopback && !fallback) fallback = candidate;
  }
  return requireLoopback ? null : fallback;
}

async function opencodeBinary(env: NodeJS.ProcessEnv): Promise<string | null> {
  const home = env.HOME ?? "";
  const candidates = [
    join(home, ".opencode/bin/opencode"),
    "/opt/homebrew/bin/opencode",
    "/usr/local/bin/opencode",
    join(home, ".local/bin/opencode"),
  ];
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  for (const dir of (env.PATH ?? "").split(":")) {
    if (!dir) continue;
    const candidate = join(dir, "opencode");
    if (existsSync(candidate)) return candidate;
  }
  const found = await runCommand(["/bin/zsh", "-lc", "command -v opencode"], 3_000);
  const trimmed = found?.trim();
  return trimmed && existsSync(trimmed) ? trimmed : null;
}

async function logURL(env: NodeJS.ProcessEnv): Promise<string | null> {
  const log = join(opencodeDataDir(env), "log/opencode.log");
  try {
    const size = statSync(log).size;
    const start = Math.max(0, size - 512 * 1024);
    const text = await Bun.file(log).slice(start).text();
    return firstURL(text, true);
  } catch {
    return null;
  }
}

/**
 * Finds the local OpenCode service. Mirrors the macOS app's discovery order:
 * explicit environment, `opencode service status`, lsof, then the server log.
 */
export async function discoverOpenCode(
  env: NodeJS.ProcessEnv = process.env,
): Promise<OpenCodeLocation | null> {
  const service = readJSON(join(configDir(env), "service.json"));
  const password =
    envString(env, "OPENCODE_SERVICE_PASSWORD") ??
    (typeof service?.password === "string" ? service.password : undefined);

  const explicit = envString(env, "OPENCODEBAR_OPENCODE_URL") ?? envString(env, "OPENCODE_SERVICE_URL");
  const url = explicit ?? (await discoverURL(env));
  if (!url || !password) return null;
  return { url: url.replace(/\/+$/, ""), password };
}

async function discoverURL(env: NodeJS.ProcessEnv): Promise<string | null> {
  const binary = await opencodeBinary(env);
  if (binary) {
    const status = await runCommand([binary, "service", "status"], 4_000);
    const url = status ? firstURL(status) : null;
    if (url) return url;
  }

  const lsof = await runCommand(
    ["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "opencode"],
    4_000,
  );
  const lsofURL = lsof ? firstURL(lsof, true) : null;
  if (lsofURL) return lsofURL;

  return logURL(env);
}

export interface SessionsOptions {
  limit?: number;
  project?: string;
  parentID?: string;
  order?: "asc" | "desc";
}

export class OpenCodeClient {
  readonly location: OpenCodeLocation;
  private readonly timeoutMs: number;

  constructor(location: OpenCodeLocation, timeoutMs = 12_000) {
    this.location = location;
    this.timeoutMs = timeoutMs;
  }

  private get authHeader(): string {
    const token = `opencode:${this.location.password}`;
    return "Basic " + Buffer.from(token, "utf8").toString("base64");
  }

  private url(path: string): string {
    return new URL(path, this.location.url).toString();
  }

  async get<T>(path: string, timeoutMs = this.timeoutMs): Promise<T> {
    let response: Response;
    try {
      response = await fetch(this.url(path), {
        headers: {
          Authorization: this.authHeader,
          Accept: "application/json",
        },
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      throw new OpenCodeError(
        `OpenCode is unreachable: ${error instanceof Error ? error.message : String(error)}`,
      );
    }

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new OpenCodeError(
        body ? `OpenCode returned HTTP ${response.status}: ${body.slice(0, 240)}` : `OpenCode returned HTTP ${response.status}`,
        response.status,
      );
    }

    try {
      return (await response.json()) as T;
    } catch (error) {
      throw new OpenCodeError(
        `Could not read OpenCode response: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  async serverInfo(): Promise<ServerInfo> {
    return this.get<ServerInfo>("/api/info");
  }

  async activeSessionIDs(): Promise<string[]> {
    const response = await this.get<ActiveSessionsResponse>("/api/session/active");
    return Object.keys(response.data ?? {});
  }

  async sessions(options: SessionsOptions = {}): Promise<Session[]> {
    const params = new URLSearchParams();
    params.set("limit", String(options.limit ?? 60));
    params.set("order", options.order ?? "desc");
    if (options.project) params.set("project", options.project);
    if (options.parentID) params.set("parentID", options.parentID);
    const response = await this.get<SessionsResponse>(`/api/session?${params}`);
    return response.data ?? [];
  }

  async session(id: string): Promise<Session> {
    const response = await this.get<{ data: Session }>(`/api/session/${encodeURIComponent(id)}`);
    return response.data;
  }

  async messages(
    id: string,
    limit = 100,
    cursor?: string | null,
    timeoutMs?: number,
  ): Promise<MessagesResponse> {
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursor) params.set("cursor", cursor);
    return this.get<MessagesResponse>(
      `/api/session/${encodeURIComponent(id)}/message?${params}`,
      timeoutMs,
    );
  }

  async projects(): Promise<Project[]> {
    return this.get<Project[]>("/api/project");
  }

  async stats(project?: string): Promise<StatsResponse> {
    const params = project ? `?project=${encodeURIComponent(project)}` : "";
    return this.get<StatsResponse>(`/api/experimental/session/stats${params}`);
  }

  /**
   * Opens the long-lived SSE stream. Returns when the connection closes; the
   * caller owns reconnects so it can back off.
   */
  async streamEvents(
    onEvent: (event: HubEvent) => void,
    signal: AbortSignal,
  ): Promise<void> {
    let response: Response;
    try {
      response = await fetch(this.url("/api/event"), {
        headers: {
          Authorization: this.authHeader,
          Accept: "text/event-stream",
        },
        signal,
      });
    } catch (error) {
      if (signal.aborted) return;
      throw new OpenCodeError(
        `Event stream failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }

    if (!response.ok || !response.body) {
      throw new OpenCodeError(`Event stream returned HTTP ${response.status}`, response.status);
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (!signal.aborted) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true }).replace(/\r\n/g, "\n");

        let boundary = buffer.indexOf("\n\n");
        while (boundary >= 0) {
          const chunk = buffer.slice(0, boundary);
          buffer = buffer.slice(boundary + 2);
          const data = chunk
            .split("\n")
            .filter((line) => line.startsWith("data:"))
            .map((line) => line.slice(5).trimStart())
            .join("\n");
          if (data) {
            try {
              const event = JSON.parse(data) as HubEvent;
              if (event && typeof event.type === "string") onEvent(event);
            } catch {
              // Ignore malformed frames; the next event may still be valid.
            }
          }
          boundary = buffer.indexOf("\n\n");
        }
      }
    } finally {
      reader.releaseLock();
    }
  }
}

export class GoUsageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GoUsageError";
  }
}

/**
 * Fetches the three Go plan windows from the console usage endpoint. Cloudflare
 * rejects requests without a conventional user agent.
 */
export async function fetchGoUsage(config: HubConfig, key: string): Promise<GoUsage> {
  let response: Response;
  try {
    response = await fetch(config.goUsageURL, {
      headers: {
        Authorization: `Bearer ${key}`,
        Accept: "application/json",
        "User-Agent": "OpenCodeBar-Hub (+https://github.com/403access/ai-tools)",
      },
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    throw new GoUsageError(
      `Could not reach the Go usage endpoint: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  if (response.status === 401) {
    throw new GoUsageError("Go API key expired — create a new one in Console");
  }
  if (!response.ok) {
    throw new GoUsageError(`Console returned HTTP ${response.status}`);
  }

  let body: { usage?: GoUsage };
  try {
    body = (await response.json()) as { usage?: GoUsage };
  } catch {
    throw new GoUsageError("Unexpected usage response");
  }
  if (!body.usage) throw new GoUsageError("Unexpected usage response");
  return body.usage;
}

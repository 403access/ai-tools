import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { configDir } from "../config.ts";
import type { Project, Session } from "../types.ts";

export const DEFAULT_HUB_URL = "http://127.0.0.1:8787";

/** The hub answers local requests quickly; cap waits so a stalled hub cannot wedge the agent. */
const REQUEST_TIMEOUT_MS = 30_000;

export interface HubLocation {
  url: string;
  token: string;
}

/** An error a tool can show verbatim, including the HTTP status when there was one. */
export class HubError extends Error {
  readonly status: number;

  constructor(message: string, status = 0) {
    super(message);
    this.name = "HubError";
    this.status = status;
  }
}

function readJSON(path: string): Record<string, unknown> | null {
  try {
    if (!existsSync(path)) return null;
    const value: unknown = JSON.parse(readFileSync(path, "utf8"));
    return value && typeof value === "object" && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

function str(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function firstNonEmpty(...values: Array<string | undefined>): string | undefined {
  return values.find((value): value is string => Boolean(value));
}

function errorMessage(payload: unknown): string | undefined {
  if (!payload || typeof payload !== "object") return undefined;
  const error = (payload as Record<string, unknown>).error;
  if (!error || typeof error !== "object") return undefined;
  const message = (error as Record<string, unknown>).message;
  return typeof message === "string" && message.trim() ? message.trim() : undefined;
}

/**
 * Resolves the hub connection the same way the apps do: environment first, then
 * the hub's pairing file, then `opencodebar.json` overrides. The hub writes the
 * pairing file on startup, so a local `make hub` needs no configuration here.
 */
export function discoverHub(env: NodeJS.ProcessEnv = process.env): HubLocation {
  const directory = configDir(env);
  const appConfig = readJSON(join(directory, "opencodebar.json"));
  const hubConfig = readJSON(join(directory, "opencodebar-hub.json"));

  const url =
    firstNonEmpty(
      str(env.OPENCODEBAR_HUB_URL),
      str(appConfig?.hubURL),
      str(hubConfig?.url),
    )?.replace(/\/+$/, "") ?? DEFAULT_HUB_URL;

  const token = firstNonEmpty(
    str(env.OPENCODEBAR_HUB_TOKEN),
    str(appConfig?.hubToken),
    str(hubConfig?.token),
  );

  if (!token) {
    throw new HubError(
      `No OpenCodeBar hub token found. Start the hub with \`make hub\`, or set ` +
        `OPENCODEBAR_HUB_TOKEN (and optionally OPENCODEBAR_HUB_URL). The hub writes ` +
        `${join(directory, "opencodebar-hub.json")} on startup.`,
    );
  }

  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      throw new Error("unsupported scheme");
    }
  } catch {
    throw new HubError(`OPENCODEBAR_HUB_URL is not a valid http(s) URL: ${url}`);
  }

  return { url, token };
}

/**
 * Thin client for the hub's HTTP API. Only the endpoints the MCP tools need are
 * wrapped here; everything else stays with the apps and the hub itself.
 */
export class HubClient {
  readonly location: HubLocation;
  private readonly fetchImpl: typeof fetch;

  constructor(location: HubLocation, fetchImpl: typeof fetch = fetch) {
    this.location = location;
    this.fetchImpl = fetchImpl;
  }

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const url = `${this.location.url}${path}`;
    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        ...init,
        headers: {
          accept: "application/json",
          authorization: `Bearer ${this.location.token}`,
          ...(init.body ? { "content-type": "application/json" } : {}),
          ...init.headers,
        },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (caught) {
      const detail = caught instanceof Error ? caught.message : String(caught);
      throw new HubError(
        `Could not reach the OpenCodeBar hub at ${this.location.url}. ` +
          `Start it with \`make hub\` and try again. (${detail})`,
      );
    }

    const text = await response.text();
    let payload: unknown = null;
    if (text.trim()) {
      try {
        payload = JSON.parse(text);
      } catch {
        payload = null;
      }
    }

    if (!response.ok) {
      throw new HubError(
        errorMessage(payload) ??
          (text.trim() || `Hub request failed with HTTP ${response.status}`),
        response.status,
      );
    }

    return payload as T;
  }

  async projects(): Promise<Project[]> {
    const payload = await this.request<Project[] | null>("/api/project");
    return Array.isArray(payload) ? payload : [];
  }

  async sessions(
    options: { project?: string; query?: string; limit?: number } = {},
  ): Promise<Session[]> {
    const params = new URLSearchParams();
    if (options.project) params.set("project", options.project);
    if (options.query) params.set("q", options.query);
    params.set("limit", String(Math.min(Math.max(options.limit ?? 20, 1), 200)));
    params.set("order", "desc");

    const payload = await this.request<{ data?: Session[] } | null>(
      `/api/session?${params.toString()}`,
    );
    return Array.isArray(payload?.data) ? payload.data : [];
  }

  async session(id: string): Promise<Session> {
    const payload = await this.request<{ data?: Session } | null>(
      `/api/session/${encodeURIComponent(id)}`,
    );
    if (!payload?.data) throw new HubError(`The hub did not return session ${id}.`, 404);
    return payload.data;
  }

  async createSession(input: { title?: string; directory: string }): Promise<Session> {
    const payload = await this.request<{ data?: Session } | null>("/api/session", {
      method: "POST",
      body: JSON.stringify({
        title: input.title,
        location: { directory: input.directory },
      }),
    });
    if (!payload?.data) throw new HubError("The hub did not return the created session.");
    return payload.data;
  }

  async promptSession(
    id: string,
    text: string,
    delivery?: "queue" | "steer",
  ): Promise<void> {
    await this.request(`/api/session/${encodeURIComponent(id)}/prompt`, {
      method: "POST",
      body: JSON.stringify(delivery ? { text, delivery } : { text }),
    });
  }
}

/** The name the apps show for a project: explicit name, then the folder name. */
export function projectDisplayName(project: Project): string {
  const name = project.name?.trim();
  if (name) return name;
  const leaf = basename(project.canonical);
  return leaf || project.canonical || project.id;
}

function fold(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function expandHome(value: string): string {
  if (value === "~") return homedir();
  if (value.startsWith("~/")) return join(homedir(), value.slice(2));
  return value;
}

function stripTrailingSlash(value: string): string {
  return value.length > 1 ? value.replace(/\/+$/, "") : value;
}

/** Every text value a user might type when naming this project. */
export function projectSearchValues(project: Project): string[] {
  return [
    project.id,
    project.canonical,
    expandHome(project.canonical),
    project.name ?? "",
    projectDisplayName(project),
    basename(project.canonical),
    ...project.sandboxes,
  ];
}

function scoreProject(project: Project, query: string): number {
  const needle = fold(query);
  const pathNeedle = fold(stripTrailingSlash(expandHome(query)));
  if (!needle) return 0;

  const id = fold(project.id);
  const canonical = fold(stripTrailingSlash(project.canonical));
  const name = fold(project.name ?? "");
  const display = fold(projectDisplayName(project));
  const leaf = fold(basename(project.canonical));

  if (id === needle) return 100;
  if (canonical === pathNeedle) return 95;
  if (display === needle || (name && name === needle) || (leaf && leaf === needle)) return 90;
  if (id.startsWith(needle) || display.startsWith(needle) || leaf.startsWith(needle)) return 70;
  if (id.includes(needle) || display.includes(needle) || leaf.includes(needle)) return 60;
  if (
    canonical.includes(pathNeedle) ||
    project.sandboxes.some((sandbox) => fold(sandbox).includes(pathNeedle))
  ) {
    return 50;
  }
  return 0;
}

export type ProjectResolution =
  | { project: Project }
  | { candidates: Project[] }
  | { error: string };

/**
 * Matches the free-form project a user names in a prompt against the hub's
 * projects. Ambiguous matches return every candidate so the agent can ask
 * instead of picking a folder with the same name in another parent.
 */
export function resolveProject(projects: Project[], query: string): ProjectResolution {
  const trimmed = query.trim();
  if (!trimmed) return { error: "A project name, id, or path is required." };

  const scored = projects
    .map((project) => ({ project, score: scoreProject(project, trimmed) }))
    .filter((entry) => entry.score > 0);

  if (scored.length === 0) {
    return { error: `No project matches "${trimmed}".` };
  }

  const top = Math.max(...scored.map((entry) => entry.score));
  const best = scored
    .filter((entry) => entry.score === top)
    .map((entry) => entry.project)
    .sort((left, right) => lastActive(right) - lastActive(left));

  const distinct = uniqueByPath(best);
  if (distinct.length === 1) return { project: distinct[0]! };
  return { candidates: distinct };
}

function projectPathKey(project: Project): string {
  return stripTrailingSlash(project.canonical).toLowerCase();
}

function uniqueByPath(projects: Project[]): Project[] {
  const seen = new Set<string>();
  const unique: Project[] = [];
  for (const project of projects) {
    const key = projectPathKey(project);
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(project);
  }
  return unique;
}

/**
 * The hub can cache more than one project id for the same checkout (OpenCode
 * reports a different id before and after a folder becomes a git work tree).
 * The tools only need the directory, so keep the most recently active row.
 */
export function uniqueProjects(projects: Project[]): Project[] {
  return uniqueByPath([...projects].sort((left, right) => lastActive(right) - lastActive(left)));
}

function lastActive(project: Project): number {
  return project.time.active ?? project.time.updated ?? project.time.created ?? 0;
}

/** A short session title from the first non-empty prompt line. */
export function deriveTitle(prompt: string, max = 80): string | undefined {
  const line = prompt
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find(Boolean);
  if (!line) return undefined;

  const cleaned = line.replace(/^#+\s*/, "").trim();
  if (!cleaned) return undefined;
  if (cleaned.length <= max) return cleaned;
  return `${cleaned.slice(0, max - 1).trimEnd()}…`;
}

import type {
  ActiveSessionsResponse,
  AgentInfo,
  HubEvent,
  MessagesResponse,
  ModelInfo,
  Project,
  ServerInfo,
  Session,
  SessionPendingItem,
  SessionsResponse,
  StatsResponse,
  TerminalCreateInput,
  TerminalUpdateInput,
} from "../types.ts";
import { OpenCodeError, type OpenCodeLocation } from "./errors.ts";

/** The shape OpenCode's PTY routes return. */
export interface Pty {
  id: string;
  title: string;
  command: string;
  args: string[];
  cwd: string;
  status: "running" | "exited";
  pid: number;
  exitCode?: number;
}

interface PtyEnvelope {
  location: { directory: string };
  data: Pty;
}

interface PtyListEnvelope {
  location: { directory: string };
  data: Pty[];
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

  private async request<T>(
    path: string,
    init: { method?: string; body?: unknown; timeoutMs?: number } = {},
  ): Promise<T> {
    let response: Response;
    try {
      response = await fetch(this.url(path), {
        method: init.method ?? "GET",
        headers: {
          Authorization: this.authHeader,
          Accept: "application/json",
          ...(init.body === undefined ? {} : { "Content-Type": "application/json" }),
        },
        body: init.body === undefined ? undefined : JSON.stringify(init.body),
        signal: AbortSignal.timeout(init.timeoutMs ?? this.timeoutMs),
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

    if (response.status === 204) return undefined as T;

    try {
      return (await response.json()) as T;
    } catch (error) {
      throw new OpenCodeError(
        `Could not read OpenCode response: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  async get<T>(path: string, timeoutMs = this.timeoutMs): Promise<T> {
    return this.request<T>(path, { timeoutMs });
  }

  async post<T>(path: string, body: unknown, timeoutMs = this.timeoutMs): Promise<T> {
    return this.request<T>(path, { method: "POST", body, timeoutMs });
  }

  async put<T>(path: string, body: unknown, timeoutMs = this.timeoutMs): Promise<T> {
    return this.request<T>(path, { method: "PUT", body, timeoutMs });
  }

  async delete<T>(path: string, timeoutMs = this.timeoutMs): Promise<T> {
    return this.request<T>(path, { method: "DELETE", timeoutMs });
  }

  /** Header the hub uses when it proxies a terminal socket upstream. */
  get authorizationHeader(): string {
    return this.authHeader;
  }

  /**
   * PTY routes are location-scoped. `location[directory]` selects the OpenCode
   * working directory whose terminals should be listed or addressed.
   */
  private withLocation(path: string, directory?: string): string {
    if (!directory) return path;
    const query = new URLSearchParams({ "location[directory]": directory });
    return `${path}${path.includes("?") ? "&" : "?"}${query}`;
  }

  async listPtys(directory?: string): Promise<PtyListEnvelope> {
    return this.get<PtyListEnvelope>(this.withLocation("/api/pty", directory));
  }

  async createPty(input: TerminalCreateInput, directory?: string): Promise<PtyEnvelope> {
    const body = {
      title: input.title,
      cwd: input.cwd,
      command: input.command,
      args: input.args,
      env: input.env,
    };
    return this.post<PtyEnvelope>(this.withLocation("/api/pty", directory), body);
  }

  async updatePty(
    id: string,
    input: TerminalUpdateInput,
    directory?: string,
  ): Promise<PtyEnvelope> {
    return this.put<PtyEnvelope>(
      this.withLocation(`/api/pty/${encodeURIComponent(id)}`, directory),
      { title: input.title, size: input.size },
    );
  }

  async removePty(id: string, directory?: string): Promise<void> {
    await this.delete<void>(
      this.withLocation(`/api/pty/${encodeURIComponent(id)}`, directory),
    );
  }

  /** WebSocket URL for a terminal, carrying the location and optional cursor. */
  ptySocketURL(id: string, options: { directory?: string; cursor?: string } = {}): string {
    const url = new URL(`/api/pty/${encodeURIComponent(id)}/connect`, this.location.url);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    if (options.directory) {
      url.searchParams.set("location[directory]", options.directory);
    }
    if (options.cursor) url.searchParams.set("cursor", options.cursor);
    return url.toString();
  }

  /** Creates a session in the given directory. The service picks the default agent/model. */
  async createSession(input: { title?: string; directory: string }): Promise<Session> {
    const response = await this.post<{ data: Session }>("/api/session", {
      title: input.title,
      location: { directory: input.directory },
    });
    return response.data;
  }

  /**
   * Creates a child session from projected history. Omitting `before` copies
   * the full history; otherwise only messages older than it are copied.
   */
  async forkSession(id: string, before?: string | null): Promise<Session> {
    const response = await this.post<{ data: Session }>(
      `/api/session/${encodeURIComponent(id)}/fork`,
      { before: before ?? null },
    );
    return response.data;
  }

  /** Changes the model used by later turns in a session. */
  async switchModel(id: string, model: { id: string; providerID: string; variant?: string }): Promise<void> {
    await this.post<void>(`/api/session/${encodeURIComponent(id)}/model`, { model });
  }

  /** Changes the agent used by later turns in a session. */
  async switchAgent(id: string, agent: string): Promise<void> {
    await this.post<void>(`/api/session/${encodeURIComponent(id)}/agent`, { agent });
  }

  /** Models available in a directory, including provider-specific config. */
  async models(directory?: string): Promise<ModelInfo[]> {
    const query = new URLSearchParams();
    if (directory) query.set("location[directory]", directory);
    const encoded = query.toString();
    const suffix = encoded ? `?${encoded}` : "";
    const response = await this.get<{ data: ModelInfo[] }>(`/api/model${suffix}`);
    return response.data ?? [];
  }

  /** Agents registered for a directory. */
  async agents(directory?: string): Promise<AgentInfo[]> {
    const query = new URLSearchParams();
    if (directory) query.set("location[directory]", directory);
    const encoded = query.toString();
    const suffix = encoded ? `?${encoded}` : "";
    const response = await this.get<{ data: AgentInfo[] }>(`/api/agent${suffix}`);
    return response.data ?? [];
  }

  /** Model OpenCode uses when a session has no explicit selection. */
  async defaultModel(directory?: string): Promise<ModelInfo | null> {
    const query = new URLSearchParams();
    if (directory) query.set("location[directory]", directory);
    const encoded = query.toString();
    const suffix = encoded ? `?${encoded}` : "";
    const response = await this.get<{ data: ModelInfo | null }>(`/api/model/default${suffix}`);
    return response.data ?? null;
  }

  /**
   * Admits a message into a session and schedules the agent loop. `delivery`
   * defaults to the service's behaviour; "queue" waits for the current run and
   * "steer" delivers into it.
   */
  async promptSession(
    id: string,
    text: string,
    delivery?: "steer" | "queue",
  ): Promise<unknown> {
    return this.post<unknown>(`/api/session/${encodeURIComponent(id)}/prompt`, {
      text,
      delivery,
    });
  }

  /**
   * Interrupts the active turn. `resume` lets OpenCode pick up pending steering
   * input and control items; queued prompts stay parked either way. An idle
   * session is a no-op and reports `interrupted: false`.
   */
  async interruptSession(id: string, resume = false): Promise<{ interrupted: boolean }> {
    const query = new URLSearchParams({ resume: resume ? "true" : "false" });
    return this.request<{ interrupted: boolean }>(
      `/api/session/${encodeURIComponent(id)}/interrupt?${query}`,
      { method: "POST" },
    );
  }

  /** Prompt inputs admitted to the session but not yet delivered to a turn. */
  async pending(id: string): Promise<SessionPendingItem[]> {
    const response = await this.get<{ data: SessionPendingItem[] }>(
      `/api/session/${encodeURIComponent(id)}/inbox`,
    );
    return response.data ?? [];
  }

  /** Removes a pending input before the running turn consumes it. */
  async cancelPending(id: string, pendingID: string): Promise<void> {
    await this.request<void>(
      `/api/session/${encodeURIComponent(id)}/inbox/${encodeURIComponent(pendingID)}`,
      { method: "DELETE" },
    );
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

  async stats(
    project?: string,
    tools: "none" | "summary" | "detail" = "detail",
  ): Promise<StatsResponse> {
    const params = new URLSearchParams({ tools });
    if (project) params.set("project", project);
    return this.get<StatsResponse>(`/api/experimental/session/stats?${params}`);
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

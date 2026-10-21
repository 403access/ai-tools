import { describe, expect, test } from "bun:test";
import { createHandler } from "../src/api.ts";
import type { HubConfig } from "../src/config.ts";
import { HubDB } from "../src/db.ts";
import { Hub } from "../src/hub.ts";
import type { Session } from "../src/types.ts";

const TOKEN = "test-token";

function config(overrides: Partial<HubConfig> = {}): HubConfig {
  return {
    host: "127.0.0.1",
    port: 8787,
    token: TOKEN,
    dbPath: ":memory:",
    configPath: "/tmp/opencodebar-hub-test.json",
    goUsageURL: "https://example.invalid/usage",
    fastPollMs: 5_000,
    slowPollMs: 60_000,
    usagePollMs: 60_000,
    logLevel: "warn",
    ...overrides,
  };
}

function session(id: string, updated: number, overrides: Partial<Session> = {}): Session {
  return {
    id,
    projectID: "prj_1",
    cost: 0.1,
    tokens: { input: 1, output: 2, reasoning: 0, cache: { read: 0, write: 0 } },
    time: { created: 1, updated },
    title: `Session ${id}`,
    location: { directory: "/tmp/project" },
    ...overrides,
  };
}

function setup(overrides: Partial<HubConfig> = {}) {
  const db = new HubDB(":memory:");
  const cfg = config(overrides);
  const hub = new Hub(cfg, db, {
    discover: async () => null,
    usageFetcher: async () => ({ rolling: { percent: 12 } }),
  });
  const handler = createHandler({ db, hub, config: cfg });
  return { db, hub, handler };
}

function request(path: string, init: RequestInit = {}, token: string | null = TOKEN): Request {
  const headers = new Headers(init.headers);
  if (token) headers.set("Authorization", `Bearer ${token}`);
  return new Request(`http://127.0.0.1:8787${path}`, { ...init, headers });
}

async function body<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

interface SessionList {
  data: Session[];
}

interface ActiveList {
  data: Record<string, { type: string }>;
}

interface MessagePage {
  data: Array<{ id: string }>;
  cursor?: { previous?: string; next?: string };
}

describe("hub API auth", () => {
  test("ping is public and reports the hub", async () => {
    const { handler, db } = setup();
    const response = await handler(request("/api/ping", {}, null));
    expect(response.status).toBe(200);
    expect((await body<{ hub: boolean }>(response)).hub).toBe(true);
    db.close();
  });

  test("data routes require the bearer token", async () => {
    const { handler, db } = setup();
    expect((await handler(request("/api/project", {}, null))).status).toBe(401);
    expect((await handler(request("/api/project", {}, "wrong"))).status).toBe(401);
    expect((await handler(request("/api/project"))).status).toBe(200);
    db.close();
  });
});

describe("hub API reads", () => {
  test("serves cached sessions, active ids and filters", async () => {
    const { db, handler } = setup();
    db.upsertSessions([
      session("ses_1", 1_000),
      session("ses_2", 2_000, { projectID: "prj_2" }),
    ]);
    db.setActive(new Set(["ses_2"]));

    const list = await body<SessionList>(await handler(request("/api/session?limit=10")));
    expect(list.data.map((s) => s.id)).toEqual(["ses_2", "ses_1"]);

    const filtered = await body<SessionList>(await handler(request("/api/session?project=prj_2")));
    expect(filtered.data.map((s) => s.id)).toEqual(["ses_2"]);

    const active = await body<ActiveList>(await handler(request("/api/session/active")));
    expect(active.data).toEqual({ ses_2: { type: "running" } });

    const detail = await body<{ data: Session }>(await handler(request("/api/session/ses_1")));
    expect(detail.data.title).toBe("Session ses_1");
    db.close();
  });

  test("serves projects in the OpenCode array shape", async () => {
    const { db, handler } = setup();
    db.replaceProjects([
      {
        id: "prj_1",
        canonical: "/tmp/project",
        time: { created: 1, updated: 2 },
        sandboxes: [],
      },
    ]);
    const response = await handler(request("/api/project"));
    const projects = await body<Array<{ canonical: string }>>(response);
    expect(Array.isArray(projects)).toBe(true);
    expect(projects[0]?.canonical).toBe("/tmp/project");
    db.close();
  });

  test("pages cached messages when OpenCode is offline", async () => {
    const { db, handler } = setup();
    db.upsertMessages("ses_1", [
      { id: "m1", type: "user", time: { created: 100 }, text: "hello" },
      { id: "m2", type: "assistant", time: { created: 200 }, content: [{ type: "text", text: "hi" }] },
    ]);
    const first = await body<MessagePage>(await handler(request("/api/session/ses_1/message?limit=1")));
    expect(first.data[0]?.id).toBe("m2");
    expect(first.cursor?.next).toBeTruthy();

    const second = await body<MessagePage>(
      await handler(
        request(`/api/session/ses_1/message?limit=1&cursor=${encodeURIComponent(first.cursor?.next ?? "")}`),
      ),
    );
    expect(second.data[0]?.id).toBe("m1");
    db.close();
  });

  test("serves cached stats and the usage state", async () => {
    const { db, handler } = setup();
    db.putStats("__global__", { steps: 7 });
    const stats = await body<{ data: { steps: number } }>(
      await handler(request("/api/experimental/session/stats")),
    );
    expect(stats.data.steps).toBe(7);

    const usage = await body<Record<string, unknown>>(await handler(request("/api/usage")));
    expect(usage).toEqual({
      data: null,
      fetchedAt: null,
      stale: false,
      error: null,
      configured: false,
    });
    db.close();
  });

  test("reports a 404 for an unknown session and route", async () => {
    const { handler, db } = setup();
    expect((await handler(request("/api/session/nope"))).status).toBe(404);
    expect((await handler(request("/api/nope"))).status).toBe(404);
    db.close();
  });
});

describe("hub events", () => {
  test("sends a greeting and broadcasts to connected sinks", () => {
    const { db, hub } = setup();
    const received: string[] = [];
    const remove = hub.addClient((event) => received.push(event.type));
    hub.broadcast({ type: "hub.sessions", data: { activeCount: 1 } });
    remove();
    hub.broadcast({ type: "hub.sessions", data: { activeCount: 2 } });
    expect(received).toEqual(["hub.connected", "hub.sessions"]);
    db.close();
  });

  test("health reflects cached rows and offline OpenCode", () => {
    const { db, hub } = setup();
    db.upsertSessions([session("ses_1", 1_000)]);
    const health = hub.health();
    expect(health.sessions).toBe(1);
    expect(health.opencode.connected).toBe(false);
    db.close();
  });
});

import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

describe("hub API writes", () => {
  test("validates session creation and prompt bodies", async () => {
    const { handler, db } = setup();

    const noLocation = await handler(
      request("/api/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: "Missing directory" }),
      }),
    );
    expect(noLocation.status).toBe(400);

    const noText = await handler(
      request("/api/session/ses_1/prompt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: "   " }),
      }),
    );
    expect(noText.status).toBe(400);

    const badDelivery = await handler(
      request("/api/session/ses_1/prompt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: "hello", delivery: "later" }),
      }),
    );
    expect(badDelivery.status).toBe(400);

    const wrongMethod = await handler(request("/api/session/ses_1/prompt"));
    expect(wrongMethod.status).toBe(405);

    db.close();
  });

  test("reports an offline OpenCode service for create and prompt", async () => {
    const { handler, db } = setup();

    const create = await handler(
      request("/api/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ location: { directory: "/tmp/project" } }),
      }),
    );
    expect(create.status).toBe(503);
    expect((await body<{ error: { message: string } }>(create)).error.message).toContain("offline");

    const prompt = await handler(
      request("/api/session/ses_1/prompt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: "hello", delivery: "queue" }),
      }),
    );
    expect(prompt.status).toBe(503);
    expect((await body<{ error: { message: string } }>(prompt)).error.message).toContain("offline");

    db.close();
  });
});

describe("hub API devices", () => {
  test("records Mac and iOS clients from request headers", async () => {
    const { handler, db } = setup();

    await handler(
      request("/api/health", {
        headers: {
          "X-OpenCodeBar-Device-Id": "mac-1",
          "X-OpenCodeBar-Device-Name": "Oli's Mac",
          "X-OpenCodeBar-Platform": "macOS",
          "X-OpenCodeBar-App-Version": "1.0.0",
        },
      }),
    );
    await handler(
      request("/api/health", {
        headers: {
          "X-OpenCodeBar-Device-Id": "ios-1",
          "X-OpenCodeBar-Device-Name": "Oli's iPhone",
          "X-OpenCodeBar-Platform": "iOS",
          "X-OpenCodeBar-App-Version": "1.0",
        },
      }),
    );

    const devices = await body<{
      data: Array<{ id: string; name: string; platform: string; connected: boolean }>;
    }>(await handler(request("/api/devices")));

    expect(devices.data.map((device) => device.id).sort()).toEqual(["ios-1", "mac-1"]);
    const mac = devices.data.find((device) => device.id === "mac-1");
    expect(mac?.platform).toBe("macOS");
    expect(mac?.connected).toBe(true);
    db.close();
  });

  test("only reports restart support when the host provides it", async () => {
    const { handler, db } = setup();
    const response = await handler(request("/api/server/restart", { method: "POST" }));
    expect(response.status).toBe(501);
    db.close();
  });
});

describe("hub API reads", () => {  test("serves cached sessions, active ids and filters", async () => {
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

  test("serves session and project changes from cached messages", async () => {
    const { db, handler } = setup();
    db.upsertSessions([session("ses_1", 1_000)]);
    db.upsertMessages("ses_1", [
      {
        id: "m1",
        type: "assistant",
        time: { created: 100 },
        content: [
          {
            type: "tool",
            id: "part_1",
            name: "edit",
            state: {
              status: "completed",
              metadata: {
                files: [
                  {
                    file: "Sources/App.swift",
                    patch: "--- a/App.swift\n+++ b/App.swift\n@@ -1 +1 @@\n-old\n+new\n",
                    additions: 1,
                    deletions: 1,
                    status: "modified",
                  },
                ],
              },
            },
          },
        ],
      },
    ]);

    const sessionChanges = await body<{ data: Array<{ file: string; patch: string }> }>(
      await handler(request("/api/session/ses_1/changes")),
    );
    expect(sessionChanges.data).toHaveLength(1);
    expect(sessionChanges.data[0]?.file).toBe("Sources/App.swift");

    const projectChanges = await body<{
      data: Array<{ file: string; sessionID: string; sessionTitle: string }>;
    }>(await handler(request("/api/project/prj_1/changes")));
    expect(projectChanges.data[0]?.sessionID).toBe("ses_1");
    expect(projectChanges.data[0]?.sessionTitle).toBe("Session ses_1");

    const empty = await body<{ data: unknown[] }>(
      await handler(request("/api/project/nope/changes")),
    );
    expect(empty.data).toEqual([]);
    db.close();
  });

  test("serves project files from the project directory", async () => {
    const directory = mkdtempSync(join(tmpdir(), "opencodebar-api-files-"));
    mkdirSync(join(directory, "nested"));
    writeFileSync(join(directory, "a.txt"), "a\n");
    writeFileSync(join(directory, "nested", "b.txt"), "b\n");

    const { db, handler } = setup();
    db.replaceProjects([
      {
        id: "prj_files",
        canonical: directory,
        time: { created: 1, updated: 2 },
        sandboxes: [],
      },
    ]);

    try {
      const response = await handler(request("/api/project/prj_files/files"));
      expect(response.status).toBe(200);
      const payload = await body<{
        data: {
          files: Array<{ path: string }>;
          vcs: string | null;
          changed: number;
          total: number;
          truncated: boolean;
        };
      }>(response);
      expect(payload.data.files.map((file) => file.path)).toEqual([
        "a.txt",
        "nested/b.txt",
      ]);
      expect(payload.data.vcs).toBeNull();
      expect(payload.data.changed).toBe(0);
      expect(payload.data.total).toBe(2);
      expect(payload.data.truncated).toBe(false);

      expect((await handler(request("/api/project/nope/files"))).status).toBe(404);
      expect(
        (await handler(request("/api/project/prj_files/files", { method: "POST" }))).status,
      ).toBe(405);
    } finally {
      rmSync(directory, { recursive: true, force: true });
      db.close();
    }
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

  test("serves cached session statistics for the session detail view", async () => {
    const { db, handler } = setup();
    db.upsertSessions([session("ses_1", 2_000)]);
    db.upsertMessages("ses_1", [
      { id: "m1", type: "user", time: { created: 100 }, text: "hello" },
      {
        id: "m2",
        type: "assistant",
        time: { created: 200 },
        content: [
          {
            type: "tool",
            id: "p1",
            name: "shell",
            state: { status: "completed" },
            time: { ran: 10, completed: 40 },
          },
          {
            type: "tool",
            id: "p2",
            name: "read",
            state: { status: "error", error: "File not found" },
            time: { ran: 5, completed: 15 },
          },
        ],
      },
    ]);

    const stats = await body<{
      data: {
        prompts: number;
        steps: number;
        tools: { totals: { calls: number; failed: number } };
        failures: Array<{ name: string; error: string }>;
      };
    }>(await handler(request("/api/session/ses_1/stats")));

    expect(stats.data.prompts).toBe(1);
    expect(stats.data.steps).toBe(1);
    expect(stats.data.tools.totals.calls).toBe(2);
    expect(stats.data.tools.totals.failed).toBe(1);
    expect(stats.data.failures[0]?.name).toBe("read");
    expect(stats.data.failures[0]?.error).toBe("File not found");

    expect((await handler(request("/api/session/nope/stats"))).status).toBe(404);
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

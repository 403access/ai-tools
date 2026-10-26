import { describe, expect, test } from "bun:test";
import { HubDB } from "../src/db.ts";
import { Hub } from "../src/hub.ts";
import { OpenCodeError } from "../src/opencode.ts";
import type { OpenCodeClient } from "../src/opencode.ts";
import { session } from "./helpers/db.ts";
import { body, config, request, setup } from "./helpers/api.ts";

function fakeClient() {
  const calls = {
    interrupts: [] as Array<{ id: string; resume: boolean }>,
    prompts: [] as Array<{ id: string; text: string }>,
  };
  const client = {
    interruptSession: async (id: string, resume = false) => {
      calls.interrupts.push({ id, resume });
      return { interrupted: true };
    },
    promptSession: async (id: string, text: string) => {
      calls.prompts.push({ id, text });
      return { ok: true };
    },
    session: async (id: string) =>
      session({ id, time: { created: 1_000, updated: 2_000 } }),
  };
  return { client: client as unknown as OpenCodeClient, calls };
}

function hubWithClient(
  db: HubDB,
  client: OpenCodeClient,
  overrides: Partial<ReturnType<typeof config>> = {},
): Hub {
  const created = new Hub(config(overrides), db, { discover: async () => null });
  created.client = client;
  return created;
}

describe("session control persistence", () => {
  test("pauses, stops and clears a session and keeps it out of the running list", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session(), session({ id: "ses_2" })]);
    db.setActive(new Set(["ses_1", "ses_2"]));

    const until = Date.now() + 60 * 60 * 1000;
    expect(db.setSessionPause("ses_1", until)).toBe(true);
    const paused = db.getSession("ses_1")!;
    expect(paused.control).toEqual({ state: "paused", at: expect.any(Number), until });
    expect(db.getSessions({ active: true }).map((item) => item.id)).toEqual(["ses_2"]);

    // OpenCode may still report the session as running; the hold wins.
    db.markActive("ses_1", true);
    expect(db.getSession("ses_1")?.control?.state).toBe("paused");
    expect(db.getSessions({ active: true }).map((item) => item.id)).toEqual(["ses_2"]);

    expect(db.setSessionStop("ses_2")).toBe(true);
    expect(db.getSession("ses_2")?.control).toEqual({ state: "stopped", at: expect.any(Number) });
    expect(db.getSessions({ active: true })).toEqual([]);

    // The timed pause is due once its deadline passes.
    expect(db.getDuePauses(until + 1)).toEqual([{ id: "ses_1", until }]);

    expect(db.clearSessionControl("ses_1")).toBe(true);
    expect(db.getSession("ses_1")?.control).toBeUndefined();
    expect(db.clearSessionControl("ses_1")).toBe(false);
    expect(db.getDuePauses(until + 1)).toEqual([]);
    db.close();
  });

  test("a later sync cannot overwrite a control", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    const until = Date.now() + 1_000;
    db.setSessionPause("ses_1", until);
    db.upsertSessions([session({ title: "Renamed" })]);
    expect(db.getSession("ses_1")?.control?.state).toBe("paused");
    expect(db.getSession("ses_1")?.title).toBe("Renamed");
    db.close();
  });
});

describe("hub control operations", () => {
  test("pause interrupts without resuming and stops the hold at the deadline", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    db.setActive(new Set(["ses_1"]));
    const { client, calls } = fakeClient();
    const hub = hubWithClient(db, client);

    const until = Date.now() + 30 * 60 * 1000;
    const paused = await hub.pauseSession("ses_1", until);
    expect(calls.interrupts).toEqual([{ id: "ses_1", resume: false }]);
    expect(paused.control).toEqual({ state: "paused", at: expect.any(Number), until });
    expect(db.getSessions({ active: true })).toEqual([]);
    db.close();
  });

  test("a direct session read keeps hub-only control state", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    const until = Date.now() + 60_000;
    db.setSessionPause("ses_1", until);
    const { client } = fakeClient();
    const hub = hubWithClient(db, client);

    const fresh = await hub.session("ses_1");
    expect(fresh?.control).toEqual({ state: "paused", at: expect.any(Number), until });
    db.close();
  });

  test("stop holds until the user continues", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    const { client, calls } = fakeClient();
    const hub = hubWithClient(db, client);

    const stopped = await hub.stopSession("ses_1");
    expect(calls.interrupts).toEqual([{ id: "ses_1", resume: false }]);
    expect(stopped.control?.state).toBe("stopped");
    expect(db.getDuePauses(Date.now() + 365 * 24 * 60 * 60 * 1000)).toEqual([]);
    db.close();
  });

  test("continue clears the hold, prompts the session, and marks it running", async () => {    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    db.setSessionStop("ses_1");
    const { client, calls } = fakeClient();
    const hub = hubWithClient(db, client);

    const continued = await hub.continueSession("ses_1");
    expect(calls.prompts).toEqual([{ id: "ses_1", text: "continue" }]);
    expect(continued.control).toBeUndefined();
    expect(db.getSessions({ active: true }).map((item) => item.id)).toEqual(["ses_1"]);
    db.close();
  });

  test("a manual prompt also releases the hold", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    db.setSessionStop("ses_1");
    const { client, calls } = fakeClient();
    const hub = hubWithClient(db, client);

    await hub.promptSession("ses_1", "try again");
    expect(calls.prompts).toEqual([{ id: "ses_1", text: "try again" }]);
    expect(db.getSession("ses_1")?.control).toBeUndefined();
    db.close();
  });

  test("resumes due pauses and releases deleted sessions", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session(), session({ id: "ses_2" })]);
    const now = Date.now();
    db.setSessionPause("ses_1", now - 1_000);
    db.setSessionPause("ses_2", now - 2_000);

    const calls = {
      prompts: [] as Array<{ id: string; text: string }>,
    };
    const client = {
      interruptSession: async () => ({ interrupted: true }),
      promptSession: async (id: string, text: string) => {
        calls.prompts.push({ id, text });
        if (id === "ses_2") throw new OpenCodeError("Session not found", 404);
        return {};
      },
      session: async (id: string) => session({ id }),
    } as unknown as OpenCodeClient;
    const hub = hubWithClient(db, client);

    await hub.resumeDueSessions();

    expect(calls.prompts).toEqual([
      { id: "ses_2", text: "continue" },
      { id: "ses_1", text: "continue" },
    ]);
    expect(db.getSession("ses_1")?.control).toBeUndefined();
    expect(db.getSession("ses_2")?.control).toBeUndefined();
    db.close();
  });

  test("keeps a due pause when OpenCode is temporarily offline", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    const until = Date.now() - 1_000;
    db.setSessionPause("ses_1", until);

    const client = {
      interruptSession: async () => ({ interrupted: true }),
      promptSession: async () => {
        throw new OpenCodeError("OpenCode is offline", 503);
      },
      session: async (id: string) => session({ id }),
    } as unknown as OpenCodeClient;
    const hub = hubWithClient(db, client);

    await hub.resumeDueSessions();
    expect(db.getSession("ses_1")?.control).toEqual({
      state: "paused",
      at: expect.any(Number),
      until,
    });
    db.close();
  });
});

describe("queued tasks", () => {
  test("stores a prompt until its start time and then sends it", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    const { client, calls } = fakeClient();
    const hub = hubWithClient(db, client);

    const until = Date.now() + 60_000;
    await hub.queueSession("ses_1", "fix the tests", until);

    const queued = db.getSession("ses_1")!;
    expect(queued.task?.status).toBe("queued");
    expect(queued.task?.queuedUntil).toBe(until);
    expect(queued.task?.queuedPrompt).toBe("fix the tests");
    expect(calls.prompts).toEqual([]);

    await hub.startQueuedSessions();
    expect(calls.prompts).toEqual([]);

    await hub.queueSession("ses_1", "fix the tests", Date.now() - 1);
    await hub.startQueuedSessions();
    expect(calls.prompts).toEqual([{ id: "ses_1", text: "fix the tests" }]);
    expect(db.getSession("ses_1")?.task?.status).toBe("working");
    db.close();
  });

  test("queues prompts beyond the concurrency limit and starts them in order", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session(), session({ id: "ses_2" }), session({ id: "ses_3" })]);
    db.setActive(new Set(["ses_1"]));
    const { client, calls } = fakeClient();
    const hub = hubWithClient(db, client, { maxConcurrentAgents: 1 });

    await hub.promptSession("ses_2", "second");
    await hub.promptSession("ses_3", "third");
    expect(calls.prompts).toEqual([]);
    expect(db.getSession("ses_2")?.task?.status).toBe("queued");
    expect(db.getSession("ses_3")?.task?.status).toBe("queued");

    // Still at the limit, so nothing starts yet.
    await hub.startQueuedSessions();
    expect(calls.prompts).toEqual([]);

    db.markActive("ses_1", false);
    await hub.startQueuedSessions();
    expect(calls.prompts).toEqual([{ id: "ses_2", text: "second" }]);
    expect(db.getSession("ses_2")?.task?.status).toBe("working");
    expect(db.getSession("ses_3")?.task?.status).toBe("queued");

    db.markActive("ses_2", false);
    await hub.startQueuedSessions();
    expect(calls.prompts).toEqual([
      { id: "ses_2", text: "second" },
      { id: "ses_3", text: "third" },
    ]);
    db.close();
  });

  test("starting now bypasses the limit and cancelling drops the prompt", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session(), session({ id: "ses_2" })]);
    db.setActive(new Set(["ses_1"]));
    const { client, calls } = fakeClient();
    const hub = hubWithClient(db, client, { maxConcurrentAgents: 1 });

    await hub.queueSession("ses_2", "go");
    const started = await hub.startQueuedSession("ses_2");
    expect(calls.prompts).toEqual([{ id: "ses_2", text: "go" }]);
    expect(started.task?.status).toBe("working");

    db.upsertSessions([session({ id: "ses_3" })]);
    await hub.queueSession("ses_3", "later");
    const cancelled = await hub.cancelQueuedSession("ses_3");
    expect(cancelled.task?.status).toBe("review");
    expect(cancelled.task?.queuedPrompt).toBeUndefined();
    db.close();
  });

  test("a queued prompt with a future start is not sent by resumeDueSessions", async () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    const { client, calls } = fakeClient();
    const hub = hubWithClient(db, client);

    await hub.queueSession("ses_1", "later", Date.now() + 60_000);
    await hub.resumeDueSessions();
    expect(calls.prompts).toEqual([]);
    db.close();
  });
});

describe("session control API", () => {
  test("validates pause deadlines", async () => {
    const { handler, db } = setup();
    const headers = { "Content-Type": "application/json" };

    const missing = await handler(
      request("/api/session/ses_1/pause", {
        method: "POST",
        headers,
        body: JSON.stringify({}),
      }),
    );
    expect(missing.status).toBe(400);
    expect((await body<{ error: { message: string } }>(missing)).error.message).toContain("required");

    const past = await handler(
      request("/api/session/ses_1/pause", {
        method: "POST",
        headers,
        body: JSON.stringify({ until: Date.now() - 1_000 }),
      }),
    );
    expect(past.status).toBe(400);

    const tooLong = await handler(
      request("/api/session/ses_1/pause", {
        method: "POST",
        headers,
        body: JSON.stringify({ forMs: 31 * 24 * 60 * 60 * 1000 }),
      }),
    );
    expect(tooLong.status).toBe(400);
    expect((await body<{ error: { message: string } }>(tooLong)).error.message).toContain("30 days");

    const wrongMethod = await handler(request("/api/session/ses_1/pause"));
    expect(wrongMethod.status).toBe(405);
    db.close();
  });

  test("reports the service as offline for pause, stop and continue", async () => {
    const { handler, db } = setup();
    const headers = { "Content-Type": "application/json" };

    const pause = await handler(
      request("/api/session/ses_1/pause", {
        method: "POST",
        headers,
        body: JSON.stringify({ forMs: 60_000 }),
      }),
    );
    expect(pause.status).toBe(503);

    for (const path of ["/api/session/ses_1/stop", "/api/session/ses_1/continue"]) {
      const response = await handler(request(path, { method: "POST", headers }));
      expect(response.status).toBe(503);
    }
    db.close();
  });

  test("queues and cancels through the API", async () => {
    const { handler, db, hub } = setup();
    db.upsertSessions([session()]);
    hub.client = fakeClient().client;
    const headers = { "Content-Type": "application/json" };

    const queued = await handler(
      request("/api/session/ses_1/queue", {
        method: "POST",
        headers,
        body: JSON.stringify({ prompt: "later", forMs: 60_000 }),
      }),
    );
    expect(queued.status).toBe(200);
    const queuedSession = (await body<{ data: import("../src/types.ts").Session }>(queued)).data;
    expect(queuedSession.task?.status).toBe("queued");
    expect(queuedSession.task?.queuedPrompt).toBe("later");

    const cancelled = await handler(
      request("/api/session/ses_1/queue", { method: "DELETE", headers }),
    );
    expect(cancelled.status).toBe(200);
    expect(
      (await body<{ data: import("../src/types.ts").Session }>(cancelled)).data.task?.status,
    ).toBe("review");

    const invalid = await handler(
      request("/api/session/ses_1/queue", {
        method: "POST",
        headers,
        body: JSON.stringify({ prompt: "" }),
      }),
    );
    expect(invalid.status).toBe(400);
    db.close();
  });

  test("serves the new operations in the OpenAPI document", async () => {
    const { handler, db } = setup();
    const response = await handler(request("/api/openapi.json", {}, null));
    const doc = await body<{
      paths: Record<string, Record<string, { operationId?: string }>>;
      components: { schemas: Record<string, unknown> };
    }>(response);

    expect(doc.paths["/api/session/{id}/pause"]?.post?.operationId).toBe("pauseSession");
    expect(doc.paths["/api/session/{id}/stop"]?.post?.operationId).toBe("stopSession");
    expect(doc.paths["/api/session/{id}/continue"]?.post?.operationId).toBe("continueSession");
    expect(doc.paths["/api/session/{id}/queue"]?.post?.operationId).toBe("queueSession");
    expect(doc.paths["/api/session/{id}/queue"]?.delete?.operationId).toBe("cancelQueuedSession");
    expect(doc.paths["/api/session/{id}/queue/start"]?.post?.operationId).toBe("startQueuedSession");
    expect(doc.components.schemas.PauseSessionRequest).toBeDefined();
    expect(doc.components.schemas.QueueSessionRequest).toBeDefined();
    expect(doc.components.schemas.SessionControl).toBeDefined();
    db.close();
  });
});

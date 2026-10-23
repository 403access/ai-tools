import { describe, expect, test } from "bun:test";
import type { Session } from "../src/types.ts";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { body, request, session, setup, type ActiveList, type MessagePage, type SessionList } from "./helpers/api.ts";

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

  test("serves an incremental session feed", async () => {
    const { db, handler } = setup();
    db.upsertSessions([session("ses_1", 1_000)]);

    const full = await body<{
      revision: number;
      full: boolean;
      sessions: Session[];
      active: string[];
    }>(await handler(request("/api/sync")));
    expect(full.full).toBe(true);
    expect(full.sessions.map((s) => s.id)).toEqual(["ses_1"]);

    db.upsertSessions([session("ses_2", 2_000)]);
    const delta = await body<{
      revision: number;
      full: boolean;
      sessions: Session[];
      deletedSessions: string[];
    }>(await handler(request(`/api/sync?since=${full.revision}`)));
    expect(delta.full).toBe(false);
    expect(delta.sessions.map((s) => s.id)).toEqual(["ses_2"]);
    expect(delta.revision).toBeGreaterThan(full.revision);

    const quiet = await body<{ sessions: Session[]; revision: number }>(
      await handler(request(`/api/sync?since=${delta.revision}`)),
    );
    expect(quiet.sessions).toEqual([]);
    expect(quiet.revision).toBe(delta.revision);
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

    const delta = await body<MessagePage>(
      await handler(request("/api/session/ses_1/message?since=150")),
    );
    expect(delta.data.map((message) => message.id)).toEqual(["m2"]);
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


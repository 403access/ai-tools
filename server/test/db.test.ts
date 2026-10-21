import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";

function session(overrides: Partial<Session> = {}): Session {
  return {
    id: "ses_1",
    projectID: "prj_1",
    cost: 0.25,
    tokens: { input: 10, output: 20, reasoning: 3, cache: { read: 4, write: 5 } },
    time: { created: 1_000, updated: 2_000 },
    title: "Fix the build",
    location: { directory: "/tmp/project" },
    ...overrides,
  };
}

function message(id: string, created: number): SessionMessage {
  return {
    id,
    type: "assistant",
    time: { created },
    content: [{ type: "text", text: `body ${id}` }],
  };
}

describe("HubDB sessions", () => {
  test("round-trips sessions and filters by project, parent and active", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([
      session({ title: "Fix the build" }),
      session({ id: "ses_2", projectID: "prj_2", title: "Write docs", time: { created: 500, updated: 3_000 } }),
      session({
        id: "ses_child",
        parentID: "ses_1",
        title: "Search logs",
        time: { created: 600, updated: 1_500 },
      }),
    ]);
    db.setActive(new Set(["ses_2"]));

    expect(db.getSessions().map((s) => s.id)).toEqual(["ses_2", "ses_1", "ses_child"]);
    expect(db.getSessions({ project: "prj_1" }).map((s) => s.id)).toEqual(["ses_1", "ses_child"]);
    expect(db.getSessions({ parentID: "ses_1" }).map((s) => s.id)).toEqual(["ses_child"]);
    expect(db.getSessions({ active: true }).map((s) => s.id)).toEqual(["ses_2"]);
    expect(db.getSessions({ q: "build" }).map((s) => s.id)).toEqual(["ses_1"]);
    db.close();
  });

  test("maps missing token fields to zeroes", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([
      session({
        tokens: undefined as unknown as Session["tokens"],
      }),
    ]);
    expect(db.getSession("ses_1")?.tokens).toEqual({
      input: 0,
      output: 0,
      reasoning: 0,
      cache: { read: 0, write: 0 },
    });
    db.close();
  });

  test("updates live cost and tokens without losing the session", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    db.updateSessionUsage("ses_1", 0.5, {
      input: 1,
      output: 2,
      reasoning: 0,
      cache: { read: 0, write: 0 },
    });
    const updated = db.getSession("ses_1");
    expect(updated?.cost).toBe(0.5);
    expect(updated?.tokens.output).toBe(2);
    db.close();
  });
});

describe("HubDB projects", () => {
  test("replace removes projects that disappeared upstream", () => {
    const db = new HubDB(":memory:");
    const project = {
      id: "prj_1",
      canonical: "/tmp/project",
      time: { created: 1, updated: 2, active: 3 },
      sandboxes: ["/tmp/sandbox"],
    };
    db.replaceProjects([project]);
    expect(db.getProjects()).toEqual([project]);
    db.replaceProjects([]);
    expect(db.getProjects()).toEqual([]);
    db.close();
  });
});

describe("HubDB messages", () => {
  test("upserts and pages newest first with the hub cursor", () => {
    const db = new HubDB(":memory:");
    db.upsertMessages("ses_1", [
      message("m1", 100),
      message("m2", 200),
      message("m3", 300),
      message("m4", 400),
    ]);

    const first = db.getMessages("ses_1", 2);
    expect(first.data.map((m) => m.id)).toEqual(["m4", "m3"]);
    expect(first.cursor?.next).toBeTruthy();

    const second = db.getMessages("ses_1", 2, first.cursor?.next);
    expect(second.data.map((m) => m.id)).toEqual(["m2", "m1"]);
    expect(second.cursor?.next).toBeUndefined();

    const decoded = decodeMessageCursor(first.cursor!.next!);
    expect(decoded?.i).toBe("m3");
    expect(encodeMessageCursor(message("x", 1)).startsWith("hub.")).toBe(true);
    db.close();
  });

  test("keeps existing content when a streaming update has no body", () => {
    const db = new HubDB(":memory:");
    db.upsertMessages("ses_1", [message("m1", 100)]);
    db.upsertMessages("ses_1", [{ id: "m1", type: "assistant", time: { created: 100 } }]);
    const page = db.getMessages("ses_1", 10);
    expect(page.data[0]?.content).toEqual([{ type: "text", text: "body m1" }]);
    db.close();
  });
});

describe("HubDB stats and usage", () => {
  test("caches stats per scope", () => {
    const db = new HubDB(":memory:");
    db.putStats("__global__", { steps: 10, activity: [{ date: "2026-10-21", steps: 10 }] });
    db.putStats("prj_1", { steps: 4 });
    expect(db.getStats("__global__")?.data.steps).toBe(10);
    expect(db.getStats("prj_1")?.data.steps).toBe(4);
    expect(db.getStats("nope")).toBeNull();
    db.close();
  });

  test("keeps the last usage payload when a refresh fails", () => {
    const db = new HubDB(":memory:");
    db.putUsage({ rolling: { percent: 42 } }, 1_000, null, 1_000);
    db.putUsageError("key expired", 2_000);
    const usage = db.getUsage();
    expect(usage.data?.rolling?.percent).toBe(42);
    expect(usage.fetchedAt).toBe(1_000);
    expect(usage.error).toBe("key expired");
    db.close();
  });
});

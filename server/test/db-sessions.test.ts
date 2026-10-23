import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";
import { session } from "./helpers/db.ts";

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


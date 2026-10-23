import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";
import { session } from "./helpers/db.ts";

describe("HubDB incremental sync", () => {
  test("returns a full snapshot, then only rows that changed", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);

    const first = db.getSync();
    expect(first.full).toBe(true);
    expect(first.revision).toBeGreaterThan(0);
    expect(first.sessions.map((s) => s.id)).toEqual(["ses_1"]);

    const quiet = db.getSync(first.revision);
    expect(quiet.full).toBe(false);
    expect(quiet.sessions).toEqual([]);
    expect(quiet.revision).toBe(first.revision);

    // An identical poll result must not bump the feed or wake the clients.
    db.upsertSessions([session()]);
    expect(db.getSync(first.revision).revision).toBe(first.revision);

    db.upsertSessions([session({ time: { created: 1_000, updated: 2_500 } })]);
    const delta = db.getSync(first.revision);
    expect(delta.full).toBe(false);
    expect(delta.sessions.map((s) => s.id)).toEqual(["ses_1"]);
    expect(delta.sessions[0]?.time.updated).toBe(2_500);
    expect(delta.revision).toBeGreaterThan(first.revision);
    db.close();
  });

  test("records project tombstones when a project disappears", () => {
    const db = new HubDB(":memory:");
    const project = {
      id: "prj_1",
      canonical: "/tmp/project",
      time: { created: 1, updated: 2 },
      sandboxes: [],
    };
    db.replaceProjects([project]);
    const first = db.getSync();
    expect(first.projects.map((p) => p.id)).toEqual(["prj_1"]);

    db.replaceProjects([]);
    const delta = db.getSync(first.revision);
    expect(delta.projects).toEqual([]);
    expect(delta.deletedProjects).toEqual(["prj_1"]);
    db.close();
  });

  test("falls back to a full snapshot for an unknown revision", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    expect(db.getSync(9_999).full).toBe(true);
    expect(db.getSync(9_999).sessions.map((s) => s.id)).toEqual(["ses_1"]);
    db.close();
  });

  test("reports usage changes from streaming updates", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    const first = db.getSync();
    db.updateSessionUsage("ses_1", 0.75, {
      input: 1,
      output: 2,
      reasoning: 0,
      cache: { read: 0, write: 0 },
    });
    const delta = db.getSync(first.revision);
    expect(delta.sessions.map((s) => s.id)).toEqual(["ses_1"]);
    expect(delta.sessions[0]?.cost).toBe(0.75);
    db.close();
  });
});


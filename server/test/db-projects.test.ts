import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";
import { session } from "./helpers/db.ts";

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


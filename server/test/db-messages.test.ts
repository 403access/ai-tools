import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";
import { message, session } from "./helpers/db.ts";

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

  test("returns only messages at or after the client's newest timestamp", () => {
    const db = new HubDB(":memory:");
    db.upsertMessages("ses_1", [message("m1", 100), message("m2", 200), message("m3", 300)]);

    expect(db.getMessagesSince("ses_1", 250).map((m) => m.id)).toEqual(["m3"]);
    // The newest message is included again so in-place streaming text updates.
    expect(db.getMessagesSince("ses_1", 300).map((m) => m.id)).toEqual(["m3"]);

    db.upsertMessages("ses_1", [
      { id: "m2", type: "assistant", time: { created: 200, completed: 400 }, content: [] },
    ]);
    expect(db.getMessagesSince("ses_1", 300).map((m) => m.id)).toEqual(["m3", "m2"]);
    db.close();
  });
});


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

  test("round-trips message errors, retries, and outcomes", () => {
    const db = new HubDB(":memory:");
    db.upsertMessages("ses_1", [
      {
        id: "m1",
        type: "idle",
        time: { created: 100 },
        outcome: "failed",
        error: {
          type: "provider.invalid-request",
          message: "Upstream request failed",
          status: 400,
          response: { body: "{\"error\":\"nope\"}" },
        },
        retry: {
          attempt: 2,
          at: 90,
          error: { type: "provider.error", message: "Retry failed" },
        },
      },
    ]);

    const stored = db.getMessages("ses_1", 10).data[0]!;
    expect(stored.outcome).toBe("failed");
    expect(stored.error?.message).toBe("Upstream request failed");
    expect(stored.error?.status).toBe(400);
    expect(stored.retry?.attempt).toBe(2);
    expect(stored.retry?.error.message).toBe("Retry failed");

    // A later streaming update without an error clears stale failure details.
    db.upsertMessages("ses_1", [{ id: "m1", type: "idle", time: { created: 100 } }]);
    expect(db.getMessages("ses_1", 10).data[0]?.error).toBeUndefined();
    db.close();
  });
});


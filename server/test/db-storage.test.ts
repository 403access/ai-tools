import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";
import { session } from "./helpers/db.ts";

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

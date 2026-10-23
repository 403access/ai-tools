import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";
import { session } from "./helpers/db.ts";

describe("HubDB devices", () => {
  test("merges a stale row when the same device reconnects with a new id", () => {
    const db = new HubDB(":memory:");
    const now = 10_000_000;
    db.upsertDevice(
      { id: "old-id", name: "Oli's iPhone", platform: "iOS", appVersion: "1.0" },
      now - 60_000,
    );
    db.upsertDevice(
      { id: "dev-new-id", name: "Oli's iPhone", platform: "iOS", appVersion: "1.1" },
      now,
    );

    const devices = db.getDevices();
    expect(devices).toHaveLength(1);
    expect(devices[0]?.id).toBe("dev-new-id");
    expect(devices[0]?.appVersion).toBe("1.1");
    expect(devices[0]?.firstSeen).toBe(now - 60_000);
    expect(devices[0]?.lastSeen).toBe(now);
    db.close();
  });

  test("keeps stable devices that share a name", () => {
    const db = new HubDB(":memory:");
    const now = 10_000_000;
    db.upsertDevice(
      { id: "dev-phone-a", name: "iPhone", platform: "iOS", appVersion: "1.0" },
      now - 60_000,
    );
    db.upsertDevice(
      { id: "dev-phone-b", name: "iPhone", platform: "iOS", appVersion: "1.0" },
      now,
    );

    expect(db.getDevices().map((device) => device.id).sort()).toEqual(["dev-phone-a", "dev-phone-b"]);
    db.close();
  });

  test("keeps recently seen legacy devices that share a name", () => {
    const db = new HubDB(":memory:");
    const now = 10_000_000;
    db.upsertDevice(
      { id: "phone-a", name: "iPhone", platform: "iOS", appVersion: "1.0" },
      now - 5_000,
    );
    db.upsertDevice(
      { id: "phone-b", name: "iPhone", platform: "iOS", appVersion: "1.0" },
      now,
    );

    expect(db.getDevices().map((device) => device.id).sort()).toEqual(["phone-a", "phone-b"]);
    db.close();
  });
});


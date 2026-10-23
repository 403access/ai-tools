import { describe, expect, test } from "bun:test";
import type { HubEvent } from "../src/types.ts";
import { request, session, setup } from "./helpers/api.ts";

describe("hub events", () => {
  test("sends a greeting and broadcasts to connected sinks", () => {
    const { db, hub } = setup();
    const received: string[] = [];
    const remove = hub.addClient((event) => received.push(event.type));
    hub.broadcast({ type: "hub.sessions", data: { activeCount: 1 } });
    remove();
    hub.broadcast({ type: "hub.sessions", data: { activeCount: 2 } });
    expect(received).toEqual(["hub.connected", "hub.sessions"]);
    db.close();
  });

  test("health reflects cached rows and offline OpenCode", () => {
    const { db, hub } = setup();
    db.upsertSessions([session("ses_1", 1_000)]);
    const health = hub.health();
    expect(health.sessions).toBe(1);
    expect(health.opencode.connected).toBe(false);
    db.close();
  });

  test("coalesces updates into one delivery per throttle window", async () => {
    const { db, hub } = setup({ eventThrottleMs: 40 });
    const received: HubEvent[] = [];
    const remove = hub.addClient((event) => received.push(event));

    hub.broadcast({
      type: "session.text.delta",
      data: { sessionID: "ses_1", partID: "part_1", delta: "hel" },
    });
    hub.broadcast({
      type: "session.text.delta",
      data: { sessionID: "ses_1", partID: "part_1", delta: "lo" },
    });
    hub.broadcast({ type: "session.tool.progress", data: { sessionID: "ses_1", id: "call_1" } });
    hub.broadcast({ type: "session.tool.progress", data: { sessionID: "ses_1", id: "call_1" } });

    // Only the greeting is immediate; the rest waits for the window to close.
    expect(received.map((event) => event.type)).toEqual(["hub.connected"]);

    await new Promise((resolve) => setTimeout(resolve, 100));
    remove();

    expect(received.map((event) => event.type)).toEqual([
      "hub.connected",
      "session.text.delta",
      "session.tool.progress",
    ]);
    expect(received[1]?.data?.delta).toBe("hello");
    db.close();
  });

  test("sends queued updates immediately when throttling is turned off", () => {
    const { db, hub } = setup({ eventThrottleMs: 1_000 });
    const received: HubEvent[] = [];
    hub.addClient((event) => received.push(event));

    hub.broadcast({ type: "hub.sessions", data: { activeCount: 1 } });
    expect(received).toHaveLength(1);

    hub.setEventThrottle(0);
    expect(received.map((event) => event.type)).toEqual(["hub.connected", "hub.sessions"]);
    expect(hub.config.eventThrottleMs).toBe(0);
    db.close();
  });
});

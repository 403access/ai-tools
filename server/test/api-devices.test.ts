import { describe, expect, test } from "bun:test";
import { body, request, session, setup, type SessionList } from "./helpers/api.ts";

describe("hub API devices", () => {
  test("records Mac and iOS clients from request headers", async () => {
    const { handler, db } = setup();

    await handler(
      request("/api/health", {
        headers: {
          "X-OpenCodeBar-Device-Id": "mac-1",
          "X-OpenCodeBar-Device-Name": "Oli's Mac",
          "X-OpenCodeBar-Platform": "macOS",
          "X-OpenCodeBar-App-Version": "1.0.0",
        },
      }),
    );
    await handler(
      request("/api/health", {
        headers: {
          "X-OpenCodeBar-Device-Id": "ios-1",
          "X-OpenCodeBar-Device-Name": "Oli's iPhone",
          "X-OpenCodeBar-Platform": "iOS",
          "X-OpenCodeBar-App-Version": "1.0",
        },
      }),
    );

    const devices = await body<{
      data: Array<{ id: string; name: string; platform: string; connected: boolean }>;
    }>(await handler(request("/api/devices")));

    expect(devices.data.map((device) => device.id).sort()).toEqual(["ios-1", "mac-1"]);
    const mac = devices.data.find((device) => device.id === "mac-1");
    expect(mac?.platform).toBe("macOS");
    expect(mac?.connected).toBe(true);
    db.close();
  });

  test("only reports restart support when the host provides it", async () => {
    const { handler, db } = setup();
    const response = await handler(request("/api/server/restart", { method: "POST" }));
    expect(response.status).toBe(501);
    db.close();
  });

  test("reads and updates the event throttle", async () => {
    const { handler, hub, db } = setup();

    const initial = await body<{ data: { eventThrottleMs: number; eventThrottleMaxMs: number } }>(
      await handler(request("/api/settings")),
    );
    expect(initial.data.eventThrottleMs).toBe(0);
    expect(initial.data.eventThrottleMaxMs).toBe(5_000);

    const update = await handler(
      request("/api/settings", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ eventThrottleMs: 400 }),
      }),
    );
    expect(update.status).toBe(200);
    expect((await body<{ data: { eventThrottleMs: number } }>(update)).data.eventThrottleMs).toBe(400);
    expect(hub.config.eventThrottleMs).toBe(400);

    const clamped = await handler(
      request("/api/settings", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ eventThrottleMs: 99_999 }),
      }),
    );
    expect((await body<{ data: { eventThrottleMs: number } }>(clamped)).data.eventThrottleMs).toBe(5_000);

    const invalid = await handler(
      request("/api/settings", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ eventThrottleMs: "fast" }),
      }),
    );
    expect(invalid.status).toBe(400);

    db.close();
  });
});


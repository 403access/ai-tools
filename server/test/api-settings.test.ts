import { describe, expect, test } from "bun:test";
import type { HubConfig } from "../src/config.ts";
import type { HubSettings } from "../src/types.ts";
import { body, request, setup } from "./helpers/api.ts";

interface SettingsResponse {
  data: HubSettings;
}

describe("hub settings API", () => {
  test("reports the event throttle and sleep preference", async () => {
    const { handler, db } = setup({ eventThrottleMs: 250, preventSleep: true });
    const response = await handler(request("/api/settings"));

    expect(response.status).toBe(200);
    const settings = (await body<SettingsResponse>(response)).data;
    expect(settings.eventThrottleMs).toBe(250);
    expect(settings.preventSleep).toBe(true);
    expect(settings.preventSleepSupported).toBe(true);
    expect(settings.maxConcurrentAgents).toBe(0);
    expect(settings.maxConcurrentAgentsMax).toBe(16);
    db.close();
  });

  test("clamps and persists the concurrent agent limit", async () => {
    let persisted: HubConfig | null = null;
    const { handler, db, hub } = setup({}, {
      persistSettings: (config) => {
        persisted = config;
      },
    });

    const response = await handler(request("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ maxConcurrentAgents: 3 }),
    }));

    expect(response.status).toBe(200);
    expect((await body<SettingsResponse>(response)).data.maxConcurrentAgents).toBe(3);
    expect(hub.config.maxConcurrentAgents).toBe(3);
    expect(persisted!.maxConcurrentAgents).toBe(3);

    const clamped = await handler(request("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ maxConcurrentAgents: 500 }),
    }));
    expect((await body<SettingsResponse>(clamped)).data.maxConcurrentAgents).toBe(16);
    db.close();
  });

  test("updates the sleep preference immediately and persists it", async () => {
    let persisted: HubConfig | null = null;
    const { handler, db, sleepGuard, hub } = setup({}, {
      persistSettings: (config) => {
        persisted = config;
      },
    });

    const response = await handler(request("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ preventSleep: true }),
    }));

    expect(response.status).toBe(200);
    expect((await body<SettingsResponse>(response)).data.preventSleep).toBe(true);
    expect(hub.config.preventSleep).toBe(true);
    expect(sleepGuard.enabled).toBe(true);
    expect(persisted).not.toBeNull();
    expect(persisted!.preventSleep).toBe(true);
    db.close();
  });

  test("accepts the throttle and sleep preference together", async () => {
    const { handler, db, sleepGuard } = setup();

    const response = await handler(request("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ eventThrottleMs: 750, preventSleep: true }),
    }));

    expect(response.status).toBe(200);
    const settings = (await body<SettingsResponse>(response)).data;
    expect(settings.eventThrottleMs).toBe(750);
    expect(settings.preventSleep).toBe(true);
    expect(sleepGuard.calls).toEqual([true]);
    db.close();
  });

  test("rejects malformed settings", async () => {
    const { handler, db } = setup();

    const invalidSleep = await handler(request("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ preventSleep: "yes" }),
    }));
    expect(invalidSleep.status).toBe(400);

    const invalidThrottle = await handler(request("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ eventThrottleMs: "fast" }),
    }));
    expect(invalidThrottle.status).toBe(400);

    const empty = await handler(request("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    }));
    expect(empty.status).toBe(400);
    db.close();
  });
});

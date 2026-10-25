import { describe, expect, test } from "bun:test";
import type { RemoteHost, RemoteStatus } from "../src/remote.ts";
import { body, request, setup } from "./helpers/api.ts";

function status(overrides: Partial<RemoteStatus> = {}): RemoteStatus {
  return {
    available: true,
    running: true,
    viewers: 0,
    version: "1.0.0",
    screenRecording: true,
    accessibility: false,
    displays: [
      {
        id: 1,
        name: "Built-in Retina Display",
        width: 1470,
        height: 956,
        scale: 2,
        primary: true,
      },
    ],
    displayID: 1,
    fps: 12,
    quality: 0.6,
    maxWidth: 1600,
    streaming: false,
    error: null,
    ...overrides,
  };
}

function fakeHost() {
  const configured: unknown[] = [];
  const permissions: unknown[] = [];
  let current = status();
  const host: RemoteHost = {
    status: async () => current,
    configure: (input) => {
      configured.push(input);
      current = { ...current, ...input };
      return current;
    },
    requestPermissions: (input) => {
      permissions.push(input);
      return current;
    },
    sendInput: () => {},
    addViewer: () => {},
    removeViewer: () => {},
    subscribe: () => () => {},
    latestFrame: () => null,
  };
  return { host, configured, permissions, set: (next: RemoteStatus) => (current = next) };
}

describe("remote desktop API", () => {
  test("reports helper status and display geometry", async () => {
    const fake = fakeHost();
    const { handler, db } = setup({}, { remote: fake.host });

    const response = await handler(request("/api/remote"));
    expect(response.status).toBe(200);
    const payload = await body<{ data: RemoteStatus }>(response);
    expect(payload.data.available).toBe(true);
    expect(payload.data.displays[0]).toMatchObject({
      id: 1,
      width: 1470,
      height: 956,
      primary: true,
    });

    db.close();
  });

  test("reports a helpful status when the hub has no remote service", async () => {
    const { handler, db } = setup();
    const payload = await body<{ data: RemoteStatus }>(
      await handler(request("/api/remote")),
    );
    expect(payload.data.available).toBe(false);
    expect(payload.data.error).toContain("does not serve remote desktop");
    db.close();
  });

  test("validates and applies configure requests", async () => {
    const fake = fakeHost();
    const { handler, db } = setup({}, { remote: fake.host });

    const configured = await handler(
      request("/api/remote/configure", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ fps: 8, quality: 0.45, maxWidth: 1280 }),
      }),
    );
    expect(configured.status).toBe(200);
    expect(fake.configured[0]).toEqual({
      fps: 8,
      quality: 0.45,
      maxWidth: 1280,
    });

    const invalid = await handler(
      request("/api/remote/configure", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ fps: "fast" }),
      }),
    );
    expect(invalid.status).toBe(400);

    const empty = await handler(
      request("/api/remote/configure", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      }),
    );
    expect(empty.status).toBe(400);

    db.close();
  });

  test("forwards permission requests and validates booleans", async () => {
    const fake = fakeHost();
    const { handler, db } = setup({}, { remote: fake.host });

    const response = await handler(
      request("/api/remote/permissions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ screenRecording: true, accessibility: false }),
      }),
    );
    expect(response.status).toBe(200);
    expect(fake.permissions[0]).toEqual({
      screenRecording: true,
      accessibility: false,
    });

    const invalid = await handler(
      request("/api/remote/permissions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ accessibility: "yes" }),
      }),
    );
    expect(invalid.status).toBe(400);

    db.close();
  });

  test("refuses a socket upgrade without a Bun server", async () => {
    const fake = fakeHost();
    const { handler, db } = setup({}, { remote: fake.host });
    const response = await handler(request("/api/remote/socket"));
    expect(response.status).toBe(501);
    db.close();
  });
});

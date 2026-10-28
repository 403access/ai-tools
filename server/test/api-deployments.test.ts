import { describe, expect, test } from "bun:test";
import { body, request, setup } from "./helpers/api.ts";
import { DeploymentScanError } from "../src/deployments.ts";
import type { Deployment, DeploymentsPayload } from "../src/types.ts";

const BASE = {
  deviceKey: "00008101-001971222298001E",
  deviceName: "Oli's iPhone",
  deviceModel: "iPhone 12 Pro",
  bundleId: "dev.opencodebar.mobile",
  appName: "OpenCodeBar",
  version: "1.0",
  build: "1",
  commitSha: "abc1234",
  branch: "main",
  worktree: "/Users/oli/Developer/ai-tools",
};

async function record(
  handler: (request: Request) => Promise<Response>,
  overrides: Record<string, unknown> = {},
): Promise<Deployment> {
  const response = await handler(
    request("/api/deployments", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...BASE, ...overrides }),
    }),
  );
  expect(response.status).toBe(201);
  return (await body<{ data: Deployment }>(response)).data;
}

describe("hub API deployments", () => {
  test("records installs, replaces the previous build, and lists current + history", async () => {
    const { handler, db } = setup();

    const first = await record(handler);
    expect(first.variant).toBe("");
    expect(first.source).toBe("script");
    expect(first.commitSha).toBe("abc1234");

    const second = await record(handler, { commitSha: "def5678", build: "2" });

    const response = await handler(request("/api/deployments"));
    const payload = await body<{ data: DeploymentsPayload }>(response);
    expect(payload.data.devices).toHaveLength(1);
    expect(payload.data.devices[0]?.name).toBe("Oli's iPhone");
    expect(payload.data.devices[0]?.current.map((entry) => entry.id)).toEqual([second.id]);
    expect(payload.data.deployments.map((entry) => entry.id)).toEqual([second.id, first.id]);
    expect(payload.data.deployments[1]?.endedAt).toBeDefined();
    expect(payload.data.deployments[1]?.endReason).toBe("replaced");

    db.close();
  });

  test("keeps variants side by side as separate current deployments", async () => {
    const { handler, db } = setup();

    await record(handler);
    const variant = await record(handler, {
      bundleId: "dev.opencodebar.mobile.review-a",
      appName: "OpenCodeBar review-a",
      variant: "review-a",
    });

    const payload = await body<{ data: DeploymentsPayload }>(
      await handler(request("/api/deployments")),
    );
    expect(variant.variant).toBe("review-a");
    expect(payload.data.devices[0]?.current.map((entry) => entry.variant).sort()).toEqual([
      "",
      "review-a",
    ]);

    db.close();
  });

  test("rejects a bundle that is not an OpenCodeBar mobile app", async () => {
    const { handler, db } = setup();
    const response = await handler(
      request("/api/deployments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...BASE, bundleId: "com.example.other" }),
      }),
    );
    expect(response.status).toBe(400);
    db.close();
  });

  test("scans devices and reports per-device errors", async () => {
    const payload: DeploymentsPayload = {
      devices: [
        {
          key: BASE.deviceKey,
          name: BASE.deviceName,
          model: "iPhone 12 Pro",
          platform: "iOS",
          state: "connected",
          connected: false,
          current: [],
        },
      ],
      deployments: [],
    };
    const { handler, db } = setup(
      {},
      {
        deployments: {
          scan: async () => ({ payload, errors: ["iPad: asleep"] }),
        },
      },
    );

    const response = await handler(request("/api/deployments/scan", { method: "POST" }));
    expect(response.status).toBe(200);
    const data = await body<{ data: DeploymentsPayload }>(response);
    expect(data.data.devices).toHaveLength(1);
    expect(data.data.errors).toEqual(["iPad: asleep"]);
    db.close();
  });

  test("returns a readable error when devicectl cannot list devices", async () => {
    const { handler, db } = setup(
      {},
      {
        deployments: {
          scan: async () => {
            throw new DeploymentScanError("Xcode is not installed");
          },
        },
      },
    );

    const response = await handler(request("/api/deployments/scan", { method: "POST" }));
    expect(response.status).toBe(409);
    const data = await body<{ error: { message: string } }>(response);
    expect(data.error.message).toBe("Xcode is not installed");
    db.close();
  });
});

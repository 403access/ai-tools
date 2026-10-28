import { describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { HubDB } from "../src/db.ts";
import { isMobileBundle, variantFromBundle } from "../src/db/deployments.ts";
import { migrate } from "../src/db/schema.ts";

const device = { key: "udid-1", name: "Test iPhone", model: "iPhone 15", platform: "iOS", state: "connected" };

describe("deployment database", () => {
  test("migrates a version 10 database to the deployment tables", () => {
    // Existing hubs skipped the v11 block because the schema version guard
    // returned early, so cover the upgrade path rather than only fresh DBs.
    const db = new Database(":memory:");
    db.exec("PRAGMA user_version = 10;");
    migrate(db);

    const version = (
      db.query("PRAGMA user_version").get() as { user_version: number }
    ).user_version;
    expect(version).toBe(11);
    const tables = (
      db
        .query(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'deployment%' ORDER BY name",
        )
        .all() as Array<{ name: string }>
    ).map((row) => row.name);
    expect(tables).toEqual(["deployment_devices", "deployments"]);
    db.close();
  });

  test("keeps the last successful sync when a scan fails", () => {
    const db = new HubDB(":memory:");
    db.upsertDeploymentDevice(device, 1_000);
    db.upsertDeploymentDevice({ ...device, state: "unavailable" }, 2_000, false);

    const stored = db.getDeploymentDevices()[0];
    expect(stored?.state).toBe("unavailable");
    expect(stored?.lastSynced).toBe(1_000);
    db.close();
  });

  test("classifies mobile bundles and variants", () => {
    expect(isMobileBundle("dev.opencodebar.mobile")).toBe(true);
    expect(isMobileBundle("dev.opencodebar.mobile.review-a")).toBe(true);
    expect(isMobileBundle("dev.opencodebar.mobile.review-a.widgets")).toBe(false);
    expect(isMobileBundle("com.example.app")).toBe(false);
    expect(variantFromBundle("dev.opencodebar.mobile")).toBe("");
    expect(variantFromBundle("dev.opencodebar.mobile.review-a")).toBe("review-a");
  });

  test("records history and closes the replaced build", () => {
    const db = new HubDB(":memory:");
    const first = db.recordDeployment(
      {
        deviceKey: device.key,
        deviceName: device.name,
        deviceModel: device.model,
        bundleId: "dev.opencodebar.mobile",
        appName: "OpenCodeBar",
        version: "1.0",
        build: "1",
        commitSha: "aaa1111",
      },
      1_000,
    );
    const second = db.recordDeployment(
      {
        deviceKey: device.key,
        deviceName: device.name,
        bundleId: "dev.opencodebar.mobile",
        appName: "OpenCodeBar",
        version: "1.0",
        build: "2",
        commitSha: "bbb2222",
      },
      2_000,
    );

    const history = db.getDeployments();
    expect(history.map((entry) => entry.id)).toEqual([second.id, first.id]);
    expect(history[1]?.endReason).toBe("replaced");
    expect(db.getCurrentDeployments().get(device.key)?.map((entry) => entry.id)).toEqual([second.id]);
    db.close();
  });

  test("a scan keeps script metadata and closes uninstalled builds", () => {
    const db = new HubDB(":memory:");
    db.recordDeployment(
      {
        deviceKey: device.key,
        deviceName: device.name,
        bundleId: "dev.opencodebar.mobile",
        appName: "OpenCodeBar",
        version: "1.0",
        build: "7",
        commitSha: "abc1234",
        branch: "main",
      },
      1_000,
    );

    // Same build seen by the scanner: the commit is preserved, no new row.
    db.syncDeploymentDevice(
      device,
      [{ bundleId: "dev.opencodebar.mobile", appName: "OpenCodeBar", version: "1.0", build: "7" }],
      2_000,
    );
    let history = db.getDeployments();
    expect(history).toHaveLength(1);
    expect(history[0]?.commitSha).toBe("abc1234");

    // Build 8 appeared from another checkout: a scan row replaces it.
    db.syncDeploymentDevice(
      device,
      [{ bundleId: "dev.opencodebar.mobile", appName: "OpenCodeBar", version: "1.0", build: "8" }],
      3_000,
    );
    // A variant appears too.
    db.syncDeploymentDevice(
      device,
      [
        { bundleId: "dev.opencodebar.mobile", appName: "OpenCodeBar", version: "1.0", build: "8" },
        {
          bundleId: "dev.opencodebar.mobile.review-b",
          appName: "OpenCodeBar review-b",
          version: "1.0",
          build: "1",
        },
      ],
      4_000,
    );
    // The main build is gone; the variant stays.
    db.syncDeploymentDevice(
      device,
      [
        {
          bundleId: "dev.opencodebar.mobile.review-b",
          appName: "OpenCodeBar review-b",
          version: "1.0",
          build: "1",
        },
      ],
      5_000,
    );

    history = db.getDeployments();
    const current = db.getCurrentDeployments().get(device.key) ?? [];
    expect(current.map((entry) => entry.variant)).toEqual(["review-b"]);
    const mainRows = history.filter((entry) => entry.bundleId === "dev.opencodebar.mobile");
    expect(mainRows[0]?.endReason).toBe("uninstalled");
    expect(mainRows[0]?.endedAt).toBe(5_000);
    expect(db.getDeploymentDevices()[0]?.state).toBe("connected");
    db.close();
  });

  test("stores a scanned device even without an OpenCodeBar build", () => {
    const db = new HubDB(":memory:");
    db.upsertDeploymentDevice({
      key: "udid-2",
      name: "iPad",
      model: "iPad Pro",
      platform: "iPadOS",
      state: "connected",
    });
    const devices = db.getDeploymentDevices();
    expect(devices).toHaveLength(1);
    expect(devices[0]?.current).toEqual([]);
    db.close();
  });
});

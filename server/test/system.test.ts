import { describe, expect, test } from "bun:test";
import type { SystemInfo } from "../src/types.ts";
import { createHandler } from "../src/api.ts";
import { HubDB } from "../src/db.ts";
import { Hub } from "../src/hub.ts";
import { parseBrewVersions, parseDF, summarizeProcesses } from "../src/system.ts";
import { body, config, request, setup } from "./helpers/api.ts";

const sample: SystemInfo = {
  generatedAt: 1_700_000_000_000,
  platform: "darwin",
  platformName: "macOS",
  host: {
    name: "Mac",
    hostname: "mac.local",
    platform: "darwin",
    platformName: "macOS",
    kernel: "24.0.0",
    arch: "arm64",
    uptime: 100,
  },
  hub: {
    version: "1.0.0",
    pid: 1,
    runtime: "Bun",
    runtimeVersion: "1.4.0",
    startedAt: 1_699_999_999_000,
    uptime: 1,
  },
  cpu: { architecture: "arm64", logicalCores: 8 },
  memory: { totalBytes: 16, freeBytes: 8, usedBytes: 8 },
  disks: [],
  network: { hostname: "mac.local", interfaces: [], dnsServers: [] },
  processes: { total: 0, topCPU: [], topMemory: [] },
  battery: null,
  thermal: null,
  security: null,
  apps: [],
  homebrew: null,
  runtimes: [],
  displays: [],
  listeningPorts: [],
  docker: null,
  notes: [],
};

describe("system endpoint", () => {
  test("requires the bearer token", async () => {
    const { db, handler } = setup();
    expect((await handler(request("/api/system", {}, null))).status).toBe(401);
    db.close();
  });

  test("returns the injected snapshot and forwards refresh=1", async () => {
    let forced = false;
    const { db, handler } = setupWithSystem(async (force) => {
      forced = force ?? false;
      return sample;
    });
    const payload = await body<{ data: SystemInfo }>(
      await handler(request("/api/system?refresh=1")),
    );
    expect(payload.data.platformName).toBe("macOS");
    expect(payload.data.memory.totalBytes).toBe(16);
    expect(forced).toBe(true);
    db.close();
  });
});

function setupWithSystem(snapshot: (force?: boolean) => Promise<SystemInfo>) {
  const db = new HubDB(":memory:");
  const cfg = config();
  const hub = new Hub(cfg, db, {
    discover: async () => null,
    usageFetcher: async () => ({}),
  });
  const handler = createHandler({ db, hub, config: cfg, system: { snapshot } });
  return { db, hub, handler };
}

describe("system parsers", () => {
  test("parses df output into byte totals", () => {
    const disks = parseDF(
      [
        "Filesystem 1024-blocks Used Available Capacity Mounted on",
        "/dev/disk3s1 100000 40000 60000 40% /",
        "devfs 100 100 0 100% /dev",
      ].join("\n"),
    );
    expect(disks).toHaveLength(1);
    expect(disks[0]?.mount).toBe("/");
    expect(disks[0]?.totalBytes).toBe(102_400_000);
    expect(disks[0]?.usedBytes).toBe(40_960_000);
  });

  test("parses Homebrew versions and marks outdated packages", () => {
    const packages = parseBrewVersions(
      "git 2.50.0\nopenssl@3 3.5.0\n",
      "formula",
      new Set(["git"]),
    );
    expect(packages).toEqual([
      { name: "git", version: "2.50.0", kind: "formula", outdated: true },
      { name: "openssl@3", version: "3.5.0", kind: "formula", outdated: false },
    ]);
  });

  test("summarizes processes by CPU and memory", () => {
    const result = summarizeProcesses(
      [
        "  12  45.0  1.5 204800 alice /usr/bin/alpha",
        "  34   2.0  8.0 1048576 bob /usr/bin/beta",
        "  56   3.0  2.0 409600 carol gamma",
      ].join("\n"),
    );
    expect(result.total).toBe(3);
    expect(result.topCPU[0]?.name).toBe("alpha");
    expect(result.topCPU[0]?.cpuPercent).toBe(45);
    expect(result.topMemory[0]?.name).toBe("beta");
    expect(result.topMemory[0]?.memoryBytes).toBe(1_073_741_824);
  });
});

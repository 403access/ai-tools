import { describe, expect, test } from "bun:test";
import type { SystemAppDetail, SystemInfo } from "../src/types.ts";
import { createHandler } from "../src/api.ts";
import { HubDB } from "../src/db.ts";
import { Hub } from "../src/hub.ts";
import {
  AppActionError,
  isXcodeApp,
  parseSimctlList,
  parseXcodeSDKs,
  performAppAction,
} from "../src/system/appDetail.ts";
import type { CommandRunner } from "../src/system/types.ts";
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
  apps: [{ name: "Xcode", path: "/Applications/Xcode.app", bundleID: "com.apple.dt.Xcode" }],
  homebrew: null,
  runtimes: [],
  displays: [],
  listeningPorts: [],
  docker: null,
  media: [],
  audio: null,
  notes: [],
};

const detail: SystemAppDetail = {
  app: sample.apps[0]!,
  info: {
    bundleID: "com.apple.dt.Xcode",
    version: "27.1",
    extensions: [],
  },
  xcode: {
    developerDir: "/Applications/Xcode.app/Contents/Developer",
    version: "27.1",
    simulators: [],
    sdks: [],
    frameworks: [],
  },
  generatedAt: 1_700_000_000_000,
};

function setupWithSystem(overrides: {
  appDetail?: (path: string) => Promise<SystemAppDetail | null>;
  appAction?: (path: string, action: string, target?: string) => Promise<SystemAppDetail>;
} = {}) {
  const db = new HubDB(":memory:");
  const cfg = config();
  const hub = new Hub(cfg, db, {
    discover: async () => null,
    usageFetcher: async () => ({}),
  });
  const handler = createHandler({
    db,
    hub,
    config: cfg,
    system: {
      snapshot: async () => sample,
      appDetail: overrides.appDetail,
      appAction: overrides.appAction,
    },
  });
  return { db, handler };
}

describe("app detail endpoint", () => {
  test("requires the bearer token", async () => {
    const { db, handler } = setup();
    const response = await handler(request("/api/system/apps/detail?path=%2FApplications%2FXcode.app", {}, null));
    expect(response.status).toBe(401);
    db.close();
  });

  test("rejects a missing or unknown application path", async () => {
    const { db, handler } = setupWithSystem({
      appDetail: async (path) => (path === detail.app.path ? detail : null),
    });
    expect((await handler(request("/api/system/apps/detail"))).status).toBe(400);

    const unknown = await handler(
      request(`/api/system/apps/detail?path=${encodeURIComponent("/Applications/Nope.app")}`),
    );
    expect(unknown.status).toBe(404);
    db.close();
  });

  test("returns the injected detail page", async () => {
    const { db, handler } = setupWithSystem({
      appDetail: async (path) => (path === detail.app.path ? detail : null),
    });
    const response = await handler(
      request(`/api/system/apps/detail?path=${encodeURIComponent(detail.app.path)}`),
    );
    expect(response.status).toBe(200);
    const payload = await body<{ data: SystemAppDetail }>(response);
    expect(payload.data.info.bundleID).toBe("com.apple.dt.Xcode");
    expect(payload.data.xcode?.developerDir).toBe(detail.xcode?.developerDir);
    db.close();
  });

  test("forwards simulator actions and returns the refreshed detail", async () => {
    const calls: Array<{ path: string; action: string; target?: string }> = [];
    const { db, handler } = setupWithSystem({
      appAction: async (path, action, target) => {
        calls.push({ path, action, target });
        return detail;
      },
    });
    const response = await handler(
      request("/api/system/apps/action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          path: detail.app.path,
          action: "simulator.boot",
          target: "ABC-123",
        }),
      }),
    );
    expect(response.status).toBe(200);
    expect(calls).toEqual([{
      path: detail.app.path,
      action: "simulator.boot",
      target: "ABC-123",
    }]);
    db.close();
  });

  test("reports unsupported management actions", async () => {
    const { db, handler } = setupWithSystem({
      appAction: async () => {
        throw new AppActionError("Unknown app action", 400);
      },
    });
    const response = await handler(
      request("/api/system/apps/action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path: detail.app.path, action: "explode" }),
      }),
    );
    expect(response.status).toBe(400);
    db.close();
  });
});

describe("app detail collectors", () => {
  test("recognises Xcode by bundle ID and name", () => {
    expect(isXcodeApp({ name: "Xcode", path: "/Applications/Xcode.app" })).toBe(true);
    expect(isXcodeApp({ name: "Xcode-beta", path: "/Applications/Xcode-beta.app" })).toBe(true);
    expect(isXcodeApp({
      name: "Xcode",
      path: "/Applications/Xcode.app",
      bundleID: "com.apple.dt.Xcode",
    })).toBe(true);
    expect(isXcodeApp({ name: "Xcodes", path: "/Applications/Xcodes.app" })).toBe(false);
  });

  test("groups simulators by runtime and sorts booted devices first", () => {
    const runtimes = parseSimctlList({
      runtimes: [{
        identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
        name: "iOS 18.0",
        platform: "iOS",
        version: "18.0",
        buildversion: "22A",
        isAvailable: true,
      }],
      devices: {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
          { udid: "A", name: "iPhone 15", state: "Shutdown", isAvailable: true },
          { udid: "B", name: "iPhone 16", state: "Booted", isAvailable: true },
          { udid: "C", name: "Old", state: "Shutdown", isAvailable: false },
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
          { udid: "D", name: "iPhone 14", state: "Shutdown", isAvailable: false },
        ],
      },
    });

    expect(runtimes).toHaveLength(2);
    expect(runtimes[0]?.identifier).toBe("com.apple.CoreSimulator.SimRuntime.iOS-18-0");
    expect(runtimes[0]?.devices.map((device) => device.udid)).toEqual(["B", "A", "C"]);
    expect(runtimes[1]?.available).toBe(false);
    expect(runtimes[1]?.version).toBe("17.0");
  });

  test("dedupes and sorts SDKs", () => {
    const sdks = parseXcodeSDKs([
      { displayName: "iOS 18.0", canonicalName: "iphoneos18.0", platform: "iphoneos", sdkVersion: "18.0" },
      { displayName: "macOS 15.0", canonicalName: "macosx15.0", platform: "macosx", sdkVersion: "15.0" },
      { displayName: "iOS 18.0", canonicalName: "iphoneos18.0", platform: "iphoneos", sdkVersion: "18.0" },
    ]);
    expect(sdks.map((sdk) => sdk.name)).toEqual(["iOS 18.0", "macOS 15.0"]);
  });

  test("runs only validated simulator actions", async () => {
    const calls: string[][] = [];
    let simctlJSON = {
      runtimes: [],
      devices: {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [{
          udid: "ABC-123",
          name: "iPhone 16",
          state: "Shutdown",
          isAvailable: true,
        }],
      },
    };

    const run: CommandRunner = async (command, args) => {
      calls.push([command, ...args]);
      if (command === "xcrun" && args[0] === "simctl" && args[1] === "list") {
        return { ok: true, stdout: JSON.stringify(simctlJSON), stderr: "" };
      }
      if (command === "xcodebuild") {
        return { ok: true, stdout: "[]", stderr: "" };
      }
      if (command === "du") {
        return { ok: true, stdout: "1024\t/Applications/Xcode.app\n", stderr: "" };
      }
      if (command === "xcrun" && args[0] === "simctl" && args[1] === "boot") {
        simctlJSON = {
          ...simctlJSON,
          devices: {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [{
              udid: "ABC-123",
              name: "iPhone 16",
              state: "Booted",
              isAvailable: true,
            }],
          },
        };
      }
      return { ok: true, stdout: "", stderr: "" };
    };

    const app = detail.app;
    const current: SystemAppDetail = {
      ...detail,
      xcode: {
        ...detail.xcode!,
        simulators: parseSimctlList(simctlJSON),
      },
    };

    const booted = await performAppAction(run, current, "simulator.boot", "ABC-123");
    expect(calls.some((call) => call[1] === "simctl" && call[2] === "boot" && call[3] === "ABC-123")).toBe(true);
    expect(booted.xcode?.simulators[0]?.devices[0]?.state).toBe("Booted");

    await expect(performAppAction(run, current, "simulator.boot", "--all")).rejects.toBeInstanceOf(AppActionError);
    await expect(performAppAction(run, current, "simulator.explode", "ABC-123")).rejects.toBeInstanceOf(AppActionError);
    expect(app.path).toBe("/Applications/Xcode.app");
  });
});

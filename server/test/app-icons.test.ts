import { afterEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { SystemInfo } from "../src/types.ts";
import { createHandler } from "../src/api.ts";
import { HubDB } from "../src/db.ts";
import { Hub } from "../src/hub.ts";
import {
  clearAppIconCache,
  hasAppIcon,
  resolveAppIcon,
} from "../src/system/appIcons.ts";
import { config, request, setup } from "./helpers/api.ts";
const directories: string[] = [];

function tempDirectory(): string {
  const directory = mkdtempSync(join(tmpdir(), "opencodebar-app-icon-"));
  directories.push(directory);
  return directory;
}

/** A minimal PNG header with the given dimensions. */
function fakePng(width: number, height: number): Uint8Array {
  const bytes = new Uint8Array(33);
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0);
  const view = new DataView(bytes.buffer);
  view.setUint32(8, 13);
  bytes.set([0x49, 0x48, 0x44, 0x52], 12);
  view.setUint32(16, width);
  view.setUint32(20, height);
  return bytes;
}

function fakeIcns(...pngs: Uint8Array[]): Uint8Array {
  const chunks = pngs.map((png) => {
    const chunk = new Uint8Array(8 + png.length);
    const view = new DataView(chunk.buffer);
    chunk.set([0x69, 0x63, 0x31, 0x30], 0); // ic10
    view.setUint32(4, chunk.length);
    chunk.set(png, 8);
    return chunk;
  });
  const total = 8 + chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const bytes = new Uint8Array(total);
  bytes.set([0x69, 0x63, 0x6e, 0x73], 0); // icns
  new DataView(bytes.buffer).setUint32(4, total);
  let offset = 8;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

function fakeMacApp(directory: string, name = "Fake"): string {
  const app = join(directory, `${name}.app`);
  const resources = join(app, "Contents", "Resources");
  mkdirSync(resources, { recursive: true });
  writeFileSync(join(resources, "AppIcon.icns"), fakeIcns(fakePng(256, 256)));
  return app;
}

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
  media: [],
  audio: null,
  notes: [],
};

afterEach(() => {
  clearAppIconCache();
  while (directories.length) {
    rmSync(directories.pop()!, { recursive: true, force: true });
  }
});

describe("installed app icons", () => {
  test("detects and renders the icon inside a macOS app bundle", async () => {
    const directory = tempDirectory();
    const app = fakeMacApp(directory);

    expect(hasAppIcon(app)).toBe(true);

    const icon = await resolveAppIcon(app);
    expect(icon).not.toBeNull();
    expect(icon?.contentType).toBe("image/png");
    expect(icon?.etag.length).toBeGreaterThan(0);
  });

  test("returns null when the app bundle has no artwork", async () => {
    const directory = tempDirectory();
    const app = join(directory, "Plain.app");
    mkdirSync(join(app, "Contents", "Resources"), { recursive: true });

    expect(hasAppIcon(app)).toBe(false);
    expect(await resolveAppIcon(app)).toBeNull();
  });

  test("serves an app icon with an ETag and revalidation", async () => {
    const directory = tempDirectory();
    const app = fakeMacApp(directory);

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
        snapshot: async () => ({
          ...sample,
          apps: [{ name: "Fake", path: app, hasIcon: true }],
        }),
      },
    });

    const response = await handler(
      request(`/api/system/apps/icon?path=${encodeURIComponent(app)}`),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("image/png");
    const etag = response.headers.get("etag");
    expect(etag).toBeTruthy();

    const revalidated = await handler(
      request(`/api/system/apps/icon?path=${encodeURIComponent(app)}`, {
        headers: { "If-None-Match": etag! },
      }),
    );
    expect(revalidated.status).toBe(304);

    const unknown = await handler(
      request("/api/system/apps/icon?path=%2Ftmp%2FUnknown.app"),
    );
    expect(unknown.status).toBe(404);
    db.close();
  });

  test("requires a bearer token", async () => {
    const { db, handler } = setup();
    const response = await handler(request("/api/system/apps/icon?path=%2Fx", {}, null));
    expect(response.status).toBe(401);
    db.close();
  });

  test("rejects a request without an app path", async () => {
    const { db, handler } = setup();
    const response = await handler(request("/api/system/apps/icon"));
    expect(response.status).toBe(400);
    db.close();
  });
});

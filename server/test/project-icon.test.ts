import { afterEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  clearProjectIconCache,
  largestPngInIcns,
  pickIconCandidate,
  pngDimensions,
  resolveProjectIcon,
  scoreIconPath,
} from "../src/projectIcon.ts";
import { request, setup } from "./helpers/api.ts";

const directories: string[] = [];

function tempDirectory(): string {
  const directory = mkdtempSync(join(tmpdir(), "opencodebar-icon-"));
  directories.push(directory);
  return directory;
}

/** A minimal PNG header with the given dimensions. Not decodable artwork, but
 * enough for the resolver's dimension checks. */
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

afterEach(() => {
  clearProjectIconCache();
  while (directories.length) {
    rmSync(directories.pop()!, { recursive: true, force: true });
  }
});

describe("scoreIconPath", () => {
  test("prefers app icon artwork over favicons and logos", () => {
    const appIcon = scoreIconPath("Mobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png");
    const icon = scoreIconPath("site/assets/icon-512.png");
    const favicon = scoreIconPath("website/static/img/favicon.png");
    const logo = scoreIconPath("docs/assets/logo.png");

    expect(appIcon).not.toBeNull();
    expect(icon).not.toBeNull();
    expect(favicon).not.toBeNull();
    expect(logo).not.toBeNull();
    expect(appIcon!).toBeGreaterThan(icon!);
    expect(favicon!).toBeGreaterThan(logo!);
  });

  test("ignores non-icons and documentation screenshots", () => {
    expect(scoreIconPath("src/components/Icon.tsx")).toBeNull();
    expect(scoreIconPath("docs/screenshots/icon-512.png")).toBeNull();
    expect(scoreIconPath("website/static/img/icon-history/website-icon-v3.png")).toBeNull();
  });

  test("accepts the common favicon and touch icon variants", () => {
    for (const path of [
      "favicon.ico",
      "favicon-32x32.png",
      "apple-touch-icon.png",
      "app-icon.png",
      "AppIcon.icns",
      "icon_512x512@2x.png",
    ]) {
      expect(scoreIconPath(path)).not.toBeNull();
    }
  });
});

describe("pickIconCandidate", () => {
  test("uses resolution to beat a tiny favicon with a large logo", () => {
    const chosen = pickIconCandidate([
      {
        path: "/p/favicon.png",
        relative: "favicon.png",
        extension: ".png",
        score: 95 - 0,
        size: 1_000,
        width: 16,
        height: 16,
        depth: 0,
      },
      {
        path: "/p/docs/assets/logo.png",
        relative: "docs/assets/logo.png",
        extension: ".png",
        score: 85 - 4,
        size: 90_000,
        width: 512,
        height: 512,
        depth: 2,
      },
    ]);

    expect(chosen?.relative).toBe("docs/assets/logo.png");
  });

  test("prefers the largest image when scores match", () => {
    const chosen = pickIconCandidate([
      {
        path: "/p/a.png",
        relative: "a.png",
        extension: ".png",
        score: 100,
        size: 10,
        width: 128,
        height: 128,
        depth: 0,
      },
      {
        path: "/p/b.png",
        relative: "b.png",
        extension: ".png",
        score: 100,
        size: 20,
        width: 512,
        height: 512,
        depth: 0,
      },
    ]);

    expect(chosen?.relative).toBe("b.png");
  });
});

describe("image containers", () => {
  test("reads PNG dimensions from the IHDR header", () => {
    expect(pngDimensions(fakePng(512, 512))).toEqual({ width: 512, height: 512 });
    expect(pngDimensions(new Uint8Array(4))).toBeNull();
  });

  test("extracts the highest-resolution PNG from an ICNS bundle", () => {
    const small = fakePng(64, 64);
    const large = fakePng(1024, 1024);
    const extracted = largestPngInIcns(fakeIcns(small, large));
    expect(extracted).not.toBeNull();
    expect(pngDimensions(extracted!)).toEqual({ width: 1024, height: 1024 });
  });
});

describe("resolveProjectIcon", () => {
  test("finds a favicon in a project that is not a git work tree", async () => {
    const directory = tempDirectory();
    mkdirSync(join(directory, "docs", "assets"), { recursive: true });
    writeFileSync(join(directory, "docs", "assets", "favicon.png"), fakePng(128, 128));

    const icon = await resolveProjectIcon(directory);
    expect(icon).not.toBeNull();
    expect(icon?.contentType).toBe("image/png");
    expect(icon?.etag.length).toBeGreaterThan(0);
  });

  test("falls back to a PNG embedded in an app icon bundle", async () => {
    const directory = tempDirectory();
    mkdirSync(join(directory, "Assets"), { recursive: true });
    writeFileSync(join(directory, "Assets", "AppIcon.icns"), fakeIcns(fakePng(512, 512)));

    const icon = await resolveProjectIcon(directory);
    expect(icon?.contentType).toBe("image/png");
    expect(pngDimensions(icon!.bytes)).toEqual({ width: 512, height: 512 });
  });

  test("returns null when the folder has no icon", async () => {
    const directory = tempDirectory();
    writeFileSync(join(directory, "README.md"), "no icon here");
    expect(await resolveProjectIcon(directory)).toBeNull();
  });

  test("rejects a missing project folder", async () => {
    expect(await resolveProjectIcon("/tmp/opencodebar-no-such-project")).toBeNull();
    expect(await resolveProjectIcon("")).toBeNull();
  });
});

describe("project icon route", () => {
  test("serves the icon, its ETag and a 304 for revalidation", async () => {
    const directory = tempDirectory();
    mkdirSync(join(directory, "site", "assets"), { recursive: true });
    writeFileSync(join(directory, "site", "assets", "icon-512.png"), fakePng(512, 512));

    const { db, handler } = setup();
    db.replaceProjects([
      {
        id: "prj_icon",
        canonical: directory,
        time: { created: 1, updated: 2 },
        sandboxes: [],
      },
    ]);

    const response = await handler(request("/api/project/prj_icon/icon"));
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("image/png");
    const etag = response.headers.get("etag");
    expect(etag).toBeTruthy();

    const revalidated = await handler(
      request("/api/project/prj_icon/icon", { headers: { "If-None-Match": etag! } }),
    );
    expect(revalidated.status).toBe(304);
    db.close();
  });

  test("returns 404 when a project has no icon", async () => {
    const directory = tempDirectory();
    writeFileSync(join(directory, "README.md"), "no icon here");

    const { db, handler } = setup();
    db.replaceProjects([
      {
        id: "prj_plain",
        canonical: directory,
        time: { created: 1, updated: 2 },
        sandboxes: [],
      },
    ]);

    const response = await handler(request("/api/project/prj_plain/icon"));
    expect(response.status).toBe(404);
    db.close();
  });
});

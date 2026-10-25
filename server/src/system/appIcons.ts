import { createHash } from "node:crypto";
import { existsSync, readdirSync, statSync } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { homedir, platform } from "node:os";
import { basename, extname, join, resolve } from "node:path";
import {
  largestPngInIcns,
  pngDimensions,
  renderImageWithSips,
} from "../projectIcon.ts";
import { readFileSafe } from "./util.ts";

/**
 * Resolves the artwork an installed application already ships with, so both
 * clients can show real icons in the System tab. macOS icons come from the
 * bundle's Info.plist or its Resources folder; Linux icons are looked up from
 * the `.desktop` file's Icon entry. Everything is cached because clients ask
 * for one icon per visible row and the files rarely change.
 */

/** How long a resolved icon (including a "no icon" result) stays cached. */
const RESOLVE_TTL_MS = 10 * 60_000;
const MAX_ICON_BYTES = 250_000;
const MAX_ICON_DIMENSION = 512;

const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg"]);

export interface AppIcon {
  bytes: Uint8Array;
  contentType: string;
  etag: string;
}

interface CacheEntry {
  at: number;
  icon: AppIcon | null;
}

const cache = new Map<string, CacheEntry>();

function isFile(path: string): boolean {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function fileSize(path: string): number {
  try {
    return statSync(path).size;
  } catch {
    return 0;
  }
}

function macResources(appPath: string): string | null {
  const resources = join(appPath, "Contents", "Resources");
  return isDirectory(resources) ? resources : null;
}

/** Names from Info.plist that usually point at the bundle's icon file. */
async function macIconNames(appPath: string): Promise<string[]> {
  const plist = join(appPath, "Contents", "Info.plist");
  if (!isFile(plist)) return [];

  try {
    const proc = Bun.spawn(
      ["/usr/bin/plutil", "-convert", "json", "-o", "-", plist],
      { stdout: "pipe", stderr: "ignore", stdin: "ignore" },
    );
    const output = await new Response(proc.stdout as ReadableStream).text();
    if (await proc.exited !== 0) return [];

    const info = JSON.parse(output) as Record<string, unknown>;
    return [info.CFBundleIconFile, info.CFBundleIconName]
      .filter((value): value is string => typeof value === "string" && Boolean(value.trim()))
      .map((value) => value.trim());
  } catch {
    return [];
  }
}

/**
 * Icon files inside an app bundle, best matches first. The plist-named file
 * wins, then artwork named after the app or a conventional AppIcon, and finally
 * any `.icns` in Resources.
 */
function orderedMacIcons(appPath: string, preferred: readonly string[]): string[] {
  const resources = macResources(appPath);
  if (!resources) return [];

  const aliases = preferred.flatMap((name) => {
    const extension = extname(name).toLowerCase();
    if (extension) return [name];
    return [`${name}.icns`, `${name}.png`];
  });

  const ordered: string[] = [];
  for (const alias of aliases) {
    const file = join(resources, alias);
    if (isFile(file) && !ordered.includes(file)) ordered.push(file);
  }

  const appName = basename(appPath, ".app").toLowerCase();
  const rank = (path: string): number => {
    const stem = basename(path, extname(path)).toLowerCase();
    if (stem === appName) return 0;
    if (/^(appicon|app icon|app|icon)$/.test(stem)) return 1;
    if (stem.includes("appicon") || stem.includes("icon")) return 2;
    return 3;
  };

  let entries: string[] = [];
  try {
    entries = readdirSync(resources);
  } catch {
    return ordered;
  }

  const icns = entries
    .filter((entry) => extname(entry).toLowerCase() === ".icns")
    .map((entry) => join(resources, entry))
    .sort((left, right) => rank(left) - rank(right) || fileSize(right) - fileSize(left));

  for (const file of icns) {
    if (!ordered.includes(file)) ordered.push(file);
  }
  return ordered;
}

/** Reads only the Icon entry; the full desktop-entry parser lives in apps.ts. */
function linuxIconName(desktopPath: string): string | undefined {
  for (const line of readFileSafe(desktopPath).split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || trimmed.startsWith("[")) continue;
    const index = trimmed.indexOf("=");
    if (index <= 0) continue;
    if (trimmed.slice(0, index).trim() !== "Icon") continue;
    return trimmed.slice(index + 1).trim() || undefined;
  }
  return undefined;
}

/** Finds the raster icon a `.desktop` entry points at. */
function findLinuxIconFile(desktopPath: string): string | null {
  const name = linuxIconName(desktopPath);
  if (!name) return null;

  const iconExtension = extname(name).toLowerCase();
  if (iconExtension && IMAGE_EXTENSIONS.has(iconExtension)) {
    return existsSync(name) && isFile(name) ? name : null;
  }
  if (name.startsWith("/")) {
    return isFile(name) ? name : null;
  }

  const roots = [
    join(homedir(), ".local", "share", "icons"),
    join(homedir(), ".icons"),
    "/usr/local/share/icons",
    "/usr/share/icons",
  ];
  const themes = ["hicolor", "Adwaita", "Yaru", "breeze", "Papirus"];
  const sizes = [
    "512x512",
    "256x256",
    "128x128",
    "96x96",
    "64x64",
    "48x48",
    "32x32",
    "24x24",
    "22x22",
    "16x16",
    "scalable",
  ];

  for (const root of roots) {
    for (const theme of themes) {
      for (const size of sizes) {
        for (const extension of IMAGE_EXTENSIONS) {
          const candidate = join(root, theme, size, "apps", `${name}${extension}`);
          if (isFile(candidate)) return candidate;
        }
      }
    }
  }

  for (const directory of [
    "/usr/share/pixmaps",
    "/usr/local/share/pixmaps",
    join(homedir(), ".local", "share", "pixmaps"),
  ]) {
    for (const extension of IMAGE_EXTENSIONS) {
      const candidate = join(directory, `${name}${extension}`);
      if (isFile(candidate)) return candidate;
    }
  }

  return null;
}

/**
 * Cheap check used while collecting the app list. Clients only request icons
 * for apps that report `hasIcon`, so browsing a machine with hundreds of apps
 * does not produce hundreds of 404s.
 */
export function hasAppIcon(path: string | null | undefined): boolean {
  const raw = path?.trim();
  if (!raw) return false;

  if (platform() === "darwin") {
    const resources = macResources(raw);
    if (!resources) return false;
    try {
      return readdirSync(resources).some((entry) => extname(entry).toLowerCase() === ".icns");
    } catch {
      return false;
    }
  }

  if (platform() === "linux") {
    return Boolean(findLinuxIconFile(raw));
  }

  return false;
}

async function findMacIconFile(appPath: string): Promise<string | null> {
  const preferred = await macIconNames(appPath);
  return orderedMacIcons(appPath, preferred)[0] ?? null;
}

async function renderIconFile(path: string): Promise<{ bytes: Uint8Array; contentType: string } | null> {
  const extension = extname(path).toLowerCase();

  if (extension === ".icns") {
    const rendered = await renderImageWithSips(path);
    if (rendered) return { bytes: rendered, contentType: "image/png" };

    try {
      const embedded = largestPngInIcns(new Uint8Array(await readFile(path)));
      return embedded ? { bytes: embedded, contentType: "image/png" } : null;
    } catch {
      return null;
    }
  }

  if (!IMAGE_EXTENSIONS.has(extension)) return null;

  let bytes: Uint8Array;
  try {
    bytes = new Uint8Array(await readFile(path));
  } catch {
    return null;
  }

  if (extension === ".png") {
    const dimensions = pngDimensions(bytes);
    const largest = Math.max(dimensions?.width ?? 0, dimensions?.height ?? 0);
    if (bytes.length <= MAX_ICON_BYTES && largest <= MAX_ICON_DIMENSION) {
      return { bytes, contentType: "image/png" };
    }
    const rendered = await renderImageWithSips(path);
    return { bytes: rendered ?? bytes, contentType: "image/png" };
  }

  const rendered = await renderImageWithSips(path);
  return {
    bytes: rendered ?? bytes,
    contentType: rendered ? "image/png" : "image/jpeg",
  };
}

async function buildIcon(appPath: string): Promise<AppIcon | null> {
  const os = platform();
  const iconPath = os === "darwin"
    ? await findMacIconFile(appPath)
    : os === "linux"
      ? findLinuxIconFile(appPath)
      : null;
  if (!iconPath) return null;

  const rendered = await renderIconFile(iconPath);
  if (!rendered) return null;

  const info = await stat(iconPath).catch(() => null);
  return {
    ...rendered,
    etag: createHash("sha1")
      .update(`${iconPath}:${info?.mtimeMs ?? 0}:${info?.size ?? 0}`)
      .digest("hex")
      .slice(0, 20),
  };
}

/** Resolves an installed app to a servable icon, caching the result. */
export async function resolveAppIcon(path: string | null | undefined): Promise<AppIcon | null> {
  const raw = path?.trim();
  if (!raw || !existsSync(raw)) return null;

  const key = resolve(raw);
  const cached = cache.get(key);
  if (cached && Date.now() - cached.at < RESOLVE_TTL_MS) return cached.icon;

  const icon = await buildIcon(key).catch(() => null);
  cache.set(key, { at: Date.now(), icon });

  if (cache.size > 250) {
    const oldest = [...cache.entries()]
      .sort((left, right) => left[1].at - right[1].at)
      .slice(0, cache.size - 250);
    for (const [entryKey] of oldest) cache.delete(entryKey);
  }

  return icon;
}

/** Clears the in-memory cache; used by tests and when the app list refreshes. */
export function clearAppIconCache(): void {
  cache.clear();
}

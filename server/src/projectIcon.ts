import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import {
  mkdtemp,
  open,
  readFile,
  readdir,
  realpath,
  rm,
  stat,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, extname, join, resolve, sep } from "node:path";

/**
 * Finds the icon a project already ships with, so both clients can show the
 * real app artwork instead of a generic folder glyph.
 *
 * The hub runs next to the project, so it can look inside the folder. Icons are
 * picked from tracked files (falling back to a bounded walk) and prioritised:
 * AppIcon assets first, then .icns bundles, apple-touch icons, favicons, icons
 * and logos. Large artwork is downscaled to 256px with macOS's `sips` when it
 * is available; otherwise the original bytes are served.
 */

/** How long a resolved icon (including a "no icon" result) stays cached. */
const RESOLVE_TTL_MS = 5 * 60_000;
const MAX_SCAN_ENTRIES = 20_000;
const MAX_WALK_DEPTH = 8;
const MAX_ICON_BYTES = 250_000;
const MAX_ICON_DIMENSION = 512;
const TARGET_ICON_SIZE = 256;

const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp", ".icns", ".svg", ".ico"]);

/** Directories that never contain project branding worth scanning. */
const SKIP_DIRECTORIES = new Set([
  ".git",
  ".build",
  ".cache",
  ".gradle",
  ".next",
  ".nuxt",
  ".output",
  ".parcel-cache",
  ".svn",
  ".turbo",
  ".venv",
  ".yarn",
  "DerivedData",
  "Pods",
  "__pycache__",
  "build",
  "dist",
  "node_modules",
  "target",
  "vendor",
  "venv",
]);

/** Paths that look like icons but are documentation or generated previews. */
const EXCLUDED_PATH = /(screenshots?|icon-history|iconset\/icon_|snapshots?)\//i;

const APP_ICON_NAME = /^app[-_ ]?icon([-_.]?\d+)?$/i;
const APPLE_TOUCH_NAME = /^apple[-_]touch[-_]icon([-_.]?\d+(x\d+)?)?$/i;
const FAVICON_NAME = /^favicon([-_.]?\d+(x\d+)?)?$/i;
const ICON_NAME = /^icon([-_.]?\d+(x\d+)?(@\dx)?)?$/i;
const LOGO_NAME = /^logo([-_.]?\d+(x\d+)?)?$/i;

export interface ProjectIcon {
  bytes: Uint8Array;
  contentType: string;
  etag: string;
}

interface IconCandidate {
  path: string;
  relative: string;
  extension: string;
  score: number;
  size: number;
  width?: number;
  height?: number;
  depth: number;
}

interface CacheEntry {
  at: number;
  icon: ProjectIcon | null;
}

const cache = new Map<string, CacheEntry>();

/**
 * Scores an icon-looking file by name and location. Returns null for files that
 * are not plausible app artwork, so callers can ignore them cheaply.
 */
export function scoreIconPath(relativePath: string): number | null {
  const normalized = relativePath.split(sep).join("/");
  if (EXCLUDED_PATH.test(normalized)) return null;

  const extension = extname(normalized).toLowerCase();
  if (!IMAGE_EXTENSIONS.has(extension)) return null;

  const name = basename(normalized, extension);
  const depth = Math.max(0, normalized.split("/").length - 1);
  const inAppIconSet = normalized.toLowerCase().includes(".appiconset/");

  let score: number;
  if (inAppIconSet && APP_ICON_NAME.test(name)) score = 120;
  else if (APP_ICON_NAME.test(name)) score = 118;
  else if (extension === ".icns") score = 110;
  else if (APPLE_TOUCH_NAME.test(name)) score = 100;
  else if (FAVICON_NAME.test(name)) score = 95;
  else if (ICON_NAME.test(name)) score = 90;
  else if (LOGO_NAME.test(name)) score = 85;
  else return null;

  // Prefer the icon near the project root over a copy in a deep docs or
  // marketing folder.
  return score - Math.min(12, Math.max(0, depth - 1) * 2);
}

/**
 * Adds a resolution bonus so a large logo beats a 16px favicon, then picks the
 * best candidate. Exported for the tests.
 */
export function pickIconCandidate(candidates: readonly IconCandidate[]): IconCandidate | null {
  let best: IconCandidate | null = null;
  let bestScore = -Infinity;

  for (const candidate of candidates) {
    const dimension = Math.max(candidate.width ?? 0, candidate.height ?? 0);
    const dimensionBonus = dimension > 0
      ? Math.round(Math.min(20, Math.log2(Math.max(1, dimension / 32)) * 4))
      : 0;
    const tinyPenalty = dimension > 0 && dimension < 48 ? 20 : 0;
    const total = candidate.score + dimensionBonus - tinyPenalty;

    if (
      total > bestScore ||
      (total === bestScore && best !== null && isLarger(candidate, best))
    ) {
      best = candidate;
      bestScore = total;
    }
  }

  return best;
}

function isLarger(candidate: IconCandidate, current: IconCandidate): boolean {
  const area = (candidate.width ?? 0) * (candidate.height ?? 0);
  const currentArea = (current.width ?? 0) * (current.height ?? 0);
  if (area !== currentArea) return area > currentArea;
  if (candidate.size !== current.size) return candidate.size > current.size;
  return candidate.relative.length < current.relative.length;
}

/** Reads PNG dimensions from the IHDR chunk. */
export function pngDimensions(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes.length < 24) return null;
  if (
    bytes[0] !== 0x89 || bytes[1] !== 0x50 || bytes[2] !== 0x4e || bytes[3] !== 0x47 ||
    bytes[4] !== 0x0d || bytes[5] !== 0x0a || bytes[6] !== 0x1a || bytes[7] !== 0x0a
  ) {
    return null;
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { width: view.getUint32(16), height: view.getUint32(20) };
}

/**
 * Extracts the highest-resolution PNG embedded in an ICNS container. Modern
 * ICNS files store PNG payloads alongside legacy bitmap types.
 */
export function largestPngInIcns(bytes: Uint8Array): Uint8Array | null {
  if (bytes.length < 8) return null;
  const ascii = (offset: number, length: number): string =>
    String.fromCharCode(...bytes.subarray(offset, offset + length));
  if (ascii(0, 4) !== "icns") return null;

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const total = Math.min(view.getUint32(4), bytes.length);
  let offset = 8;
  let best: Uint8Array | null = null;
  let bestArea = 0;

  while (offset + 8 <= total) {
    const length = view.getUint32(offset + 4);
    if (length < 8 || offset + length > bytes.length) break;
    const payload = bytes.subarray(offset + 8, offset + length);
    const dimensions = pngDimensions(payload);
    if (dimensions) {
      const area = dimensions.width * dimensions.height;
      if (area > bestArea) {
        best = payload;
        bestArea = area;
      }
    }
    offset += length;
  }

  return best;
}

async function imageDimensions(
  path: string,
  extension: string,
): Promise<{ width?: number; height?: number }> {
  if (extension === ".png") {
    const handle = await open(path, "r").catch(() => null);
    if (!handle) return {};
    try {
      const header = Buffer.alloc(32);
      const { bytesRead } = await handle.read(header, 0, header.length, 0);
      return pngDimensions(header.subarray(0, bytesRead)) ?? {};
    } finally {
      await handle.close().catch(() => {});
    }
  }

  // ICNS bundles usually contain at least a 512px representation. Treating them
  // as large lets them win over a tiny favicon; the real resolution is chosen
  // when the PNG payload is extracted.
  if (extension === ".icns") return { width: 1024, height: 1024 };
  return {};
}

async function gitFileList(root: string): Promise<string[] | null> {
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn(
      ["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
      { stdout: "pipe", stderr: "ignore", stdin: "ignore" },
    );
  } catch {
    return null;
  }

  const read = (async (): Promise<string[] | null> => {
    try {
      const output = await new Response(proc.stdout as ReadableStream).text();
      const code = await proc.exited;
      if (code !== 0) return null;
      return output.split("\0").filter(Boolean);
    } catch {
      return null;
    }
  })();

  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<null>((resolveTimeout) => {
    timer = setTimeout(() => {
      try {
        proc.kill();
      } catch {
        // Already exited.
      }
      resolveTimeout(null);
    }, 4_000);
  });

  try {
    return await Promise.race([read, timeout]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function walkFileList(root: string): Promise<string[]> {
  const files: string[] = [];
  const stack: Array<{ directory: string; relative: string; depth: number }> = [
    { directory: root, relative: "", depth: 0 },
  ];

  while (stack.length && files.length < MAX_SCAN_ENTRIES) {
    const current = stack.pop()!;
    let entries;
    try {
      entries = await readdir(current.directory, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (files.length >= MAX_SCAN_ENTRIES) break;
      const relative = current.relative ? `${current.relative}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        if (current.depth >= MAX_WALK_DEPTH || SKIP_DIRECTORIES.has(entry.name)) continue;
        stack.push({
          directory: join(current.directory, entry.name),
          relative,
          depth: current.depth + 1,
        });
      } else if (entry.isFile()) {
        files.push(relative);
      }
    }
  }

  return files;
}

async function candidatesFor(root: string): Promise<IconCandidate[]> {
  const listed = (await gitFileList(root)) ?? (await walkFileList(root));
  const candidates: IconCandidate[] = [];

  for (const relative of listed) {
    const score = scoreIconPath(relative);
    if (score === null) continue;

    const path = join(root, relative);
    const info = await stat(path).catch(() => null);
    if (!info?.isFile()) continue;

    const extension = extname(relative).toLowerCase();
    const dimensions: { width?: number; height?: number } = await imageDimensions(path, extension)
      .catch(() => ({}));
    candidates.push({
      path,
      relative,
      extension,
      score,
      size: info.size,
      width: dimensions.width,
      height: dimensions.height,
      depth: relative.split("/").length - 1,
    });
  }

  return candidates;
}

/** Runs `sips` to rasterise/resize artwork into a bounded PNG. */
async function renderWithSips(path: string): Promise<Uint8Array | null> {
  const directory = await mkdtemp(join(tmpdir(), "opencodebar-icon-")).catch(() => null);
  if (!directory) return null;
  const output = join(directory, "icon.png");

  try {
    const proc = Bun.spawn(
      ["/usr/bin/sips", "-Z", String(TARGET_ICON_SIZE), "-s", "format", "png", path, "--out", output],
      { stdout: "ignore", stderr: "ignore", stdin: "ignore" },
    );
    const code = await proc.exited;
    if (code !== 0) return null;
    const bytes = await readFile(output);
    return bytes.length ? new Uint8Array(bytes) : null;
  } catch {
    return null;
  } finally {
    await rm(directory, { recursive: true, force: true }).catch(() => {});
  }
}

async function renderCandidate(
  candidate: IconCandidate,
): Promise<{ bytes: Uint8Array; contentType: string } | null> {
  if (candidate.extension === ".icns") {
    // sips understands ICNS and picks the best representation; the manual
    // extractor keeps things working when the host is not macOS.
    const rendered = await renderWithSips(candidate.path);
    const embedded = rendered ?? largestPngInIcns(await readFile(candidate.path));
    return embedded ? { bytes: embedded, contentType: "image/png" } : null;
  }

  if (candidate.extension === ".svg" || candidate.extension === ".ico") {
    const rendered = await renderWithSips(candidate.path);
    return rendered ? { bytes: rendered, contentType: "image/png" } : null;
  }

  const bytes = new Uint8Array(await readFile(candidate.path));

  if (candidate.extension === ".png") {
    const dimension = Math.max(candidate.width ?? 0, candidate.height ?? 0);
    if (bytes.length <= MAX_ICON_BYTES && dimension <= MAX_ICON_DIMENSION) {
      return { bytes, contentType: "image/png" };
    }
    return { bytes: (await renderWithSips(candidate.path)) ?? bytes, contentType: "image/png" };
  }

  const contentType = candidate.extension === ".webp" ? "image/webp" : "image/jpeg";
  const rendered = await renderWithSips(candidate.path);
  return rendered ? { bytes: rendered, contentType: "image/png" } : { bytes, contentType };
}

function etagFor(candidate: IconCandidate, modified: number): string {
  return createHash("sha1")
    .update(`${candidate.path}:${modified}:${candidate.size}`)
    .digest("hex")
    .slice(0, 20);
}

async function buildIcon(directory: string): Promise<ProjectIcon | null> {
  let info;
  try {
    info = await stat(directory);
  } catch {
    return null;
  }
  if (!info.isDirectory()) return null;

  const root = await realpath(directory).catch(() => resolve(directory));
  const candidates = await candidatesFor(root);
  const best = pickIconCandidate(candidates);
  if (!best) return null;

  const rendered = await renderCandidate(best);
  if (!rendered) return null;

  const modified = await stat(best.path).then((value) => value.mtimeMs).catch(() => 0);
  return {
    bytes: rendered.bytes,
    contentType: rendered.contentType,
    etag: etagFor(best, modified),
  };
}

/** Resolves a project directory to a servable icon, caching the result. */
export async function resolveProjectIcon(directory: string | null | undefined): Promise<ProjectIcon | null> {
  const raw = directory?.trim();
  if (!raw || !existsSync(raw)) return null;

  const key = resolve(raw);
  const cached = cache.get(key);
  if (cached && Date.now() - cached.at < RESOLVE_TTL_MS) return cached.icon;

  const icon = await buildIcon(key).catch(() => null);
  cache.set(key, { at: Date.now(), icon });

  if (cache.size > 100) {
    // Drop the oldest entries; icons are cheap to resolve again.
    const oldest = [...cache.entries()]
      .sort((left, right) => left[1].at - right[1].at)
      .slice(0, cache.size - 100);
    for (const [entryKey] of oldest) cache.delete(entryKey);
  }

  return icon;
}

/** Clears the in-memory cache; used by tests and when a project refreshes. */
export function clearProjectIconCache(): void {
  cache.clear();
}

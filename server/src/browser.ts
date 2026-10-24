import { existsSync } from "node:fs";
import { lstat, open, readdir, readFile, readlink, realpath, stat } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, extname, isAbsolute, join, parse, resolve } from "node:path";
import type {
  HostDirectory,
  HostFileContent,
  HostFileEntry,
  HostFileRoot,
  HostRawFile,
} from "./types.ts";

/**
 * Read-only browser for the machine running the hub. The clients use it to
 * navigate the host's folders and preview text or images. Paths are absolute
 * (with `~` allowed) and symlinks are resolved before a file is opened.
 */

const MAX_ENTRIES = 2_000;
const MAX_PREVIEW_BYTES = 512 * 1024;
const MAX_RAW_BYTES = 25 * 1024 * 1024;
const STAT_CONCURRENCY = 32;

const IMAGE_TYPES: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".bmp": "image/bmp",
  ".tif": "image/tiff",
  ".tiff": "image/tiff",
  ".heic": "image/heic",
  ".heif": "image/heif",
  ".avif": "image/avif",
  ".ico": "image/x-icon",
};

const TEXT_TYPES: Record<string, string> = {
  ".txt": "text/plain",
  ".md": "text/markdown",
  ".markdown": "text/markdown",
  ".json": "application/json",
  ".jsonc": "application/json",
  ".yaml": "text/yaml",
  ".yml": "text/yaml",
  ".toml": "text/toml",
  ".xml": "application/xml",
  ".html": "text/html",
  ".htm": "text/html",
  ".css": "text/css",
  ".scss": "text/x-scss",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".cjs": "text/javascript",
  ".ts": "text/typescript",
  ".tsx": "text/typescript",
  ".jsx": "text/javascript",
  ".swift": "text/x-swift",
  ".py": "text/x-python",
  ".rb": "text/x-ruby",
  ".go": "text/x-go",
  ".rs": "text/x-rust",
  ".java": "text/x-java",
  ".kt": "text/x-kotlin",
  ".c": "text/x-c",
  ".h": "text/x-c",
  ".cpp": "text/x-c++",
  ".hpp": "text/x-c++",
  ".m": "text/x-objective-c",
  ".mm": "text/x-objective-c++",
  ".cs": "text/x-csharp",
  ".php": "text/x-php",
  ".sh": "text/x-shellscript",
  ".zsh": "text/x-shellscript",
  ".bash": "text/x-shellscript",
  ".fish": "text/x-shellscript",
  ".sql": "text/plain",
  ".svg": "image/svg+xml",
  ".plist": "application/xml",
  ".entitlements": "application/xml",
  ".lock": "text/plain",
  ".log": "text/plain",
  ".csv": "text/csv",
  ".tsv": "text/tab-separated-values",
  ".env": "text/plain",
  ".gitignore": "text/plain",
  ".gitattributes": "text/plain",
  ".dockerignore": "text/plain",
  ".editorconfig": "text/plain",
};

/** Files that hold hub/OpenCode credentials are never served back to clients. */
function deniedPaths(): string[] {
  const home = homedir();
  const config = process.env.XDG_CONFIG_HOME?.trim() || join(home, ".config");
  const data = process.env.XDG_DATA_HOME?.trim() || join(home, ".local", "share");
  return [
    join(config, "opencode", "opencodebar-hub.json"),
    join(config, "opencode", "service.json"),
    join(config, "opencode", "auth.json"),
    join(data, "opencode", "auth.json"),
  ];
}

export class FileBrowserError extends Error {
  readonly status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.name = "FileBrowserError";
    this.status = status;
  }
}

function expandPath(input: string | null | undefined): string {
  const raw = input?.trim();
  if (!raw) throw new FileBrowserError("A path is required", 400);
  let expanded = raw;
  if (expanded === "~") expanded = homedir();
  else if (expanded.startsWith("~/")) expanded = join(homedir(), expanded.slice(2));
  if (!isAbsolute(expanded)) {
    throw new FileBrowserError("The path must be absolute (or start with ~)", 400);
  }
  return resolve(expanded);
}

function denied(candidate: string): boolean {
  const normalized = resolve(candidate);
  return deniedPaths().some((entry) => resolve(entry) === normalized);
}

async function resolveExisting(input: string | null | undefined): Promise<string> {
  const requested = expandPath(input);
  if (denied(requested)) {
    throw new FileBrowserError("This file is not available to clients", 403);
  }
  const real = await realpath(requested).catch(() => null);
  if (!real) throw new FileBrowserError("Path not found", 404);
  if (denied(real)) {
    throw new FileBrowserError("This file is not available to clients", 403);
  }
  return real;
}

function roots(): HostFileRoot[] {
  const home = homedir();
  const candidates: HostFileRoot[] = [
    { name: "Home", path: home, kind: "home" },
    { name: "Root", path: parse(home).root, kind: "root" },
  ];

  if (process.platform === "darwin") {
    candidates.push(
      { name: "Applications", path: "/Applications", kind: "applications" },
      { name: "Volumes", path: "/Volumes", kind: "volumes" },
    );
  } else if (process.platform === "linux") {
    candidates.push(
      { name: "/etc", path: "/etc", kind: "etc" },
      { name: "/var/log", path: "/var/log", kind: "logs" },
      { name: "/mnt", path: "/mnt", kind: "mounts" },
    );
  } else {
    candidates.push(
      { name: "Program Files", path: "C:\\Program Files", kind: "applications" },
      { name: "Users", path: join(parse(home).root, "Users"), kind: "users" },
    );
  }

  candidates.push({ name: "Temp", path: tmpdir(), kind: "temp" });

  const seen = new Set<string>();
  return candidates.filter((entry) => {
    if (seen.has(entry.path) || !existsSync(entry.path)) return false;
    seen.add(entry.path);
    return true;
  });
}

function modeString(mode: number): string {
  const flags = ["r", "w", "x"];
  let result = "";
  for (let offset = 6; offset >= 0; offset -= 3) {
    const bits = (mode >> offset) & 0o7;
    result += bits & 0o4 ? flags[0] : "-";
    result += bits & 0o2 ? flags[1] : "-";
    result += bits & 0o1 ? flags[2] : "-";
  }
  return result;
}

async function mapLimit<T, R>(
  values: T[],
  limit: number,
  mapper: (value: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(values.length);
  let index = 0;
  const workers = Array.from({ length: Math.min(limit, values.length) }, async () => {
    while (index < values.length) {
      const current = index;
      index += 1;
      const value = values[current];
      if (value === undefined) continue;
      results[current] = await mapper(value, current);
    }
  });
  await Promise.all(workers);
  return results;
}

function entrySort(left: HostFileEntry, right: HostFileEntry): number {
  if (left.isDirectory !== right.isDirectory) return left.isDirectory ? -1 : 1;
  const result = left.name.localeCompare(right.name, undefined, { numeric: true, sensitivity: "base" });
  if (result !== 0) return result;
  return left.name.localeCompare(right.name);
}

export async function listDirectory(input: string | null | undefined): Promise<HostDirectory> {
  const directory = await resolveExisting(input);

  let info;
  try {
    info = await stat(directory);
  } catch {
    throw new FileBrowserError("Path not found", 404);
  }
  if (!info.isDirectory()) {
    throw new FileBrowserError("The path is not a directory", 400);
  }

  let names: string[];
  try {
    names = await readdir(directory);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new FileBrowserError(`Cannot read this folder: ${message}`, 403);
  }

  const total = names.length;
  // Keep truncation deterministic: slice the alphabetically first 2,000 names
  // instead of whatever order the filesystem returned.
  names.sort((left, right) => left.localeCompare(right, undefined, { numeric: true, sensitivity: "base" }));
  const selected = names.slice(0, MAX_ENTRIES);
  const entries = await mapLimit(selected, STAT_CONCURRENCY, async (name): Promise<HostFileEntry> => {
    const entryPath = join(directory, name);
    const entry: HostFileEntry = {
      name,
      path: entryPath,
      kind: "other",
      isDirectory: false,
      hidden: name.startsWith("."),
    };

    try {
      const linkInfo = await lstat(entryPath);
      entry.size = linkInfo.isFile() ? linkInfo.size : undefined;
      entry.modified = linkInfo.mtimeMs;
      entry.permissions = modeString(linkInfo.mode);

      if (linkInfo.isSymbolicLink()) {
        entry.kind = "symlink";
        entry.linkTarget = await readlink(entryPath).catch(() => undefined);
        const target = await stat(entryPath).catch(() => null);
        entry.isDirectory = target?.isDirectory() ?? false;
      } else if (linkInfo.isDirectory()) {
        entry.kind = "directory";
        entry.isDirectory = true;
      } else if (linkInfo.isFile()) {
        entry.kind = "file";
      }
    } catch {
      entry.error = "Not readable";
    }

    return entry;
  });

  entries.sort(entrySort);

  const parentPath = dirname(directory);
  return {
    path: directory,
    name: basename(directory) || directory,
    parent: parentPath === directory ? null : parentPath,
    roots: roots(),
    entries,
    total,
    truncated: total > selected.length,
  };
}

function mimeFor(path: string): string {
  const ext = extname(path).toLowerCase();
  return IMAGE_TYPES[ext] ?? TEXT_TYPES[ext] ?? "application/octet-stream";
}

function isImage(path: string): boolean {
  return Boolean(IMAGE_TYPES[extname(path).toLowerCase()]);
}

function looksBinary(bytes: Uint8Array): boolean {
  const sample = bytes.subarray(0, Math.min(bytes.length, 8_192));
  if (sample.length === 0) return false;
  let controls = 0;
  for (const byte of sample) {
    if (byte === 0) return true;
    // Tab, newline and carriage return are fine; other C0 controls are not.
    if (byte < 9 || (byte > 13 && byte < 32)) controls += 1;
  }
  return controls / sample.length > 0.05;
}

async function readPrefix(path: string, maxBytes: number): Promise<{ bytes: Uint8Array; truncated: boolean }> {
  const handle = await open(path, "r");
  try {
    const buffer = Buffer.alloc(maxBytes);
    const read = await handle.read(buffer, 0, maxBytes, 0);
    return {
      bytes: new Uint8Array(buffer.buffer, buffer.byteOffset, read.bytesRead),
      truncated: read.bytesRead >= maxBytes,
    };
  } finally {
    await handle.close();
  }
}

export async function readFileContent(input: string | null | undefined): Promise<HostFileContent> {
  const path = await resolveExisting(input);
  const info = await stat(path);
  if (!info.isFile()) throw new FileBrowserError("The path is not a file", 400);

  const mime = mimeFor(path);
  const base = {
    path,
    name: basename(path),
    size: info.size,
    modified: info.mtimeMs,
    mime,
  };

  if (isImage(path)) {
    return {
      ...base,
      kind: "image",
      truncated: false,
      maxBytes: MAX_PREVIEW_BYTES,
    };
  }

  const prefix = await readPrefix(path, MAX_PREVIEW_BYTES);
  if (looksBinary(prefix.bytes)) {
    return {
      ...base,
      kind: "binary",
      truncated: false,
      maxBytes: MAX_PREVIEW_BYTES,
    };
  }

  const content = new TextDecoder("utf-8", { fatal: false }).decode(prefix.bytes);
  return {
    ...base,
    kind: "text",
    content,
    truncated: prefix.truncated || info.size > MAX_PREVIEW_BYTES,
    maxBytes: MAX_PREVIEW_BYTES,
  };
}

export async function readRawFile(input: string | null | undefined): Promise<HostRawFile> {
  const path = await resolveExisting(input);
  const info = await stat(path);
  if (!info.isFile()) throw new FileBrowserError("The path is not a file", 400);
  if (info.size > MAX_RAW_BYTES) {
    throw new FileBrowserError(`Files larger than ${Math.round(MAX_RAW_BYTES / 1_048_576)} MB cannot be previewed`, 413);
  }
  const bytes = await readFile(path);
  return {
    bytes,
    mime: mimeFor(path),
    name: basename(path),
    size: info.size,
  };
}

import { existsSync } from "node:fs";
import { readdir, realpath, stat } from "node:fs/promises";
import { join, relative, resolve, sep } from "node:path";
import type { ProjectFile, ProjectFileStatus, ProjectFiles } from "./types.ts";

/**
 * Files inside a project directory, with the working-tree status git reports.
 *
 * The hub runs on the same machine as the project, so it can read the directory
 * directly instead of asking OpenCode. Git is used when the folder is a work
 * tree: `ls-files` gives tracked and untracked-but-not-ignored files, and
 * `status` marks the ones that differ from the index. Other folders fall back
 * to a bounded recursive walk with common build/cache directories skipped.
 */

const MAX_FILES = 20_000;
const MAX_DEPTH = 24;

/** Directories that are rarely useful in a project file browser. */
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

export class ProjectFilesError extends Error {
  readonly status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.name = "ProjectFilesError";
    this.status = status;
  }
}

/** Parses `git status --porcelain=v1 -z` into a path → status map. */
export function parseGitStatus(output: string): Map<string, ProjectFileStatus> {
  const statuses = new Map<string, ProjectFileStatus>();
  for (const entry of output.split("\0")) {
    if (entry.length < 4) continue;
    const code = entry.slice(0, 2);
    if (code === "!!") continue;
    const path = normalizePath(entry.slice(3));
    if (!path) continue;

    let status: ProjectFileStatus = "modified";
    if (code.includes("D")) status = "deleted";
    else if (code === "??" || code.includes("A") || code.includes("C")) status = "added";
    else if (code.includes("R")) status = "renamed";
    statuses.set(path, status);
  }
  return statuses;
}

function normalizePath(path: string): string {
  return sep === "/" ? path : path.split(sep).join("/");
}

async function runGit(
  directory: string,
  args: string[],
  timeoutMs = 6_000,
): Promise<string | null> {
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn(["git", "-C", directory, ...args], {
      stdout: "pipe",
      stderr: "ignore",
      stdin: "ignore",
    });
  } catch {
    return null;
  }

  const read = (async (): Promise<string | null> => {
    try {
      const output = await new Response(proc.stdout as ReadableStream).text();
      const code = await proc.exited;
      return code === 0 ? output : null;
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
    }, timeoutMs);
  });

  try {
    return await Promise.race([read, timeout]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function gitFiles(directory: string): Promise<ProjectFiles | null> {
  const inside = await runGit(directory, ["rev-parse", "--is-inside-work-tree"]);
  if (inside?.trim() !== "true") return null;

  const [listed, status] = await Promise.all([
    runGit(directory, ["ls-files", "-z", "--cached", "--others", "--exclude-standard"]),
    runGit(directory, [
      "status",
      "--porcelain=v1",
      "-z",
      "--untracked-files=all",
      "--no-renames",
    ]),
  ]);
  if (listed === null) return null;

  const statuses = parseGitStatus(status ?? "");
  const seen = new Set<string>();
  const files: ProjectFile[] = [];
  for (const raw of listed.split("\0")) {
    const path = normalizePath(raw);
    if (!path || seen.has(path)) continue;
    seen.add(path);
    const state = statuses.get(path);
    files.push(state ? { path, status: state } : { path });
  }
  // Staged deletions are no longer in the index, so the listing above omits
  // them. Keep them visible as changed entries until the deletion is committed.
  for (const [path, state] of statuses) {
    if (seen.has(path)) continue;
    seen.add(path);
    files.push({ path, status: state });
  }
  files.sort((left, right) => left.path.localeCompare(right.path));

  const total = files.length;
  const changed = files.reduce((count, file) => count + (file.status ? 1 : 0), 0);
  return {
    files: files.slice(0, MAX_FILES),
    vcs: "git",
    total,
    changed,
    truncated: total > MAX_FILES,
  };
}

interface WalkResult {
  files: ProjectFile[];
  total: number;
  truncated: boolean;
}

async function walkFiles(root: string): Promise<WalkResult> {
  const files: string[] = [];
  const stack: Array<{ directory: string; depth: number }> = [
    { directory: root, depth: 0 },
  ];
  let truncated = false;

  while (stack.length) {
    const { directory, depth } = stack.pop()!;
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      continue;
    }
    entries.sort((left, right) => left.name.localeCompare(right.name));

    for (const entry of entries) {
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) {
        if (depth >= MAX_DEPTH || SKIP_DIRECTORIES.has(entry.name)) continue;
        stack.push({ directory: join(directory, entry.name), depth: depth + 1 });
      } else if (entry.isFile()) {
        if (files.length >= MAX_FILES) {
          truncated = true;
          break;
        }
        files.push(normalizePath(relative(root, join(directory, entry.name))));
      }
    }

    if (truncated) break;
  }

  files.sort((left, right) => left.localeCompare(right));
  return {
    files: files.map((path) => ({ path })),
    total: files.length,
    truncated,
  };
}

export async function listProjectFiles(directory: string): Promise<ProjectFiles> {
  const raw = directory?.trim();
  if (!raw) throw new ProjectFilesError("Project has no directory", 400);

  const resolved = resolve(raw);
  if (!existsSync(resolved)) {
    throw new ProjectFilesError("Project folder not found", 404);
  }

  let info;
  try {
    info = await stat(resolved);
  } catch {
    throw new ProjectFilesError("Project folder not found", 404);
  }
  if (!info.isDirectory()) {
    throw new ProjectFilesError("Project path is not a directory", 400);
  }

  const real = await realpath(resolved).catch(() => resolved);
  const git = await gitFiles(real);
  if (git) return git;

  const walked = await walkFiles(real);
  return {
    files: walked.files,
    vcs: null,
    total: walked.total,
    changed: 0,
    truncated: walked.truncated,
  };
}

import { existsSync } from "node:fs";
import { mkdir, realpath, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";

/**
 * Clones a git repository on the hub host so a client can start a session in a
 * project that does not exist yet.
 *
 * Only authenticated clients can reach this, and the hub already reads and
 * writes project folders for sessions and file browsing. The clone is still
 * deliberately narrow: a URL or GitHub shorthand, no shell interpolation, no
 * overwriting an existing folder, and a bounded runtime with terminal prompts
 * disabled so a private repository cannot hang a request forever.
 */

const CLONE_TIMEOUT_MS = 300_000;
const MAX_URL_LENGTH = 2_048;
const MAX_NAME_LENGTH = 255;

export class CloneError extends Error {
  readonly status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.name = "CloneError";
    this.status = status;
  }
}

export interface CloneInput {
  url: string;
  parent?: string;
  name?: string;
  directory?: string;
}

export interface ClonedRepository {
  directory: string;
  name: string;
  url: string;
}

function expandHome(path: string): string {
  if (path === "~") return homedir();
  if (path.startsWith("~/")) return join(homedir(), path.slice(2));
  return path;
}

function isValidFolderName(name: string): boolean {
  return (
    name.length > 0 &&
    name.length <= MAX_NAME_LENGTH &&
    name !== "." &&
    name !== ".." &&
    !name.startsWith("-") &&
    !/[/\\\u0000-\u001f]/.test(name)
  );
}

/**
 * Accepts full git URLs, scp-style SSH remotes, and GitHub `owner/repo`
 * shorthand. Returns the URL to pass to git plus the folder name it suggests.
 */
export function normalizeRepositoryURL(input: string): { url: string; name: string } {
  const raw = input.trim();
  if (!raw) throw new CloneError("A repository URL is required", 400);
  if (raw.length > MAX_URL_LENGTH) {
    throw new CloneError("Repository URL is too long", 400);
  }
  if (/[\u0000-\u0020\u007f]/.test(raw)) {
    throw new CloneError("Repository URL cannot contain spaces or control characters", 400);
  }
  if (raw.startsWith("-")) {
    throw new CloneError("Repository URL cannot start with a dash", 400);
  }

  let normalized = raw;
  if (/^github\.com\/[^/]+\/[^/]+\/?$/i.test(raw)) {
    normalized = `https://${raw}`;
  } else if (/^[^/:@\s]+\/[^/\s]+\/?$/.test(raw) && !raw.includes("://")) {
    normalized = `https://github.com/${raw}`;
  }

  const scp = /^[^@\s/:]+@[^:\s/]+:(.+)$/.exec(normalized);
  const hasScheme = /^(https?|ssh|git|file):\/\//i.test(normalized);
  if (!scp && !hasScheme) {
    throw new CloneError(
      "Use a git URL (https://, ssh://, git://, file://) or GitHub owner/repo shorthand",
      400,
    );
  }

  let path: string;
  if (scp) {
    path = scp[1]!;
  } else {
    try {
      path = new URL(normalized).pathname;
    } catch {
      throw new CloneError("Repository URL is not valid", 400);
    }
  }

  const segment = path.replace(/\/+$/, "").split("/").filter(Boolean).pop() ?? "";
  let name: string;
  try {
    name = decodeURIComponent(segment);
  } catch {
    throw new CloneError("Repository URL has an invalid path", 400);
  }
  name = name.replace(/\.git$/i, "");
  if (!isValidFolderName(name)) {
    throw new CloneError("Could not infer a folder name from the repository URL", 400);
  }

  return { url: normalized, name };
}

function redactCredentials(text: string): string {
  return text
    .replace(/\u001b\[[0-9;]*m/g, "")
    .replace(/(https?:\/\/)[^/\s@]+@/gi, "$1***@");
}

function cloneFailureDetail(stderr: string): string {
  const lines = redactCredentials(stderr)
    .split(/\r\n|\r|\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(-3);
  const detail = lines.join(" ");
  if (!detail) return "git clone failed";
  return detail.length > 500 ? `${detail.slice(0, 500)}…` : detail;
}

async function runGitClone(url: string, destination: string): Promise<void> {
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn(
      ["git", "clone", "--", url, destination],
      {
        cwd: dirname(destination),
        env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
        stdin: "ignore",
        stdout: "pipe",
        stderr: "pipe",
      },
    );
  } catch {
    throw new CloneError("Git is not available on the hub host", 500);
  }

  const stdout = new Response(proc.stdout as ReadableStream).text();
  const stderr = new Response(proc.stderr as ReadableStream).text();

  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, rejectTimeout) => {
    timer = setTimeout(() => {
      try {
        proc.kill();
      } catch {
        // Already exited.
      }
      rejectTimeout(
        new CloneError(
          `Cloning timed out after ${Math.round(CLONE_TIMEOUT_MS / 1_000)} seconds`,
          504,
        ),
      );
    }, CLONE_TIMEOUT_MS);
  });

  const completed = Promise.all([proc.exited, stdout, stderr]);
  // The timeout path stops observing this promise; keep a late stream or exit
  // error from becoming an unhandled rejection in the hub process.
  completed.catch(() => {});

  try {
    const [code, , errorOutput] = await Promise.race([completed, timeout]);
    if (code !== 0) {
      throw new CloneError(
        `Could not clone repository: ${cloneFailureDetail(errorOutput)}`,
        422,
      );
    }
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export async function cloneRepository(input: CloneInput): Promise<ClonedRepository> {
  const repository = normalizeRepositoryURL(input.url);

  let destination: string;
  if (input.directory?.trim()) {
    const raw = expandHome(input.directory.trim());
    if (!isAbsolute(raw)) {
      throw new CloneError("Destination directory must be an absolute path", 400);
    }
    destination = resolve(raw);
    if (!isValidFolderName(basename(destination))) {
      throw new CloneError("Destination directory needs a folder name", 400);
    }
  } else {
    const rawParent = input.parent?.trim() || "~/Developer";
    const expanded = expandHome(rawParent);
    if (!isAbsolute(expanded)) {
      throw new CloneError("Parent directory must be an absolute path", 400);
    }
    const folderName = input.name?.trim() || repository.name;
    if (!isValidFolderName(folderName)) {
      throw new CloneError("Folder name is not valid", 400);
    }
    destination = join(resolve(expanded), folderName);
  }

  if (existsSync(destination)) {
    throw new CloneError(`A folder already exists at ${destination}`, 409);
  }

  const parent = dirname(destination);
  try {
    await mkdir(parent, { recursive: true });
  } catch {
    throw new CloneError(`Could not create the parent folder ${parent}`, 400);
  }

  let info;
  try {
    info = await stat(parent);
  } catch {
    throw new CloneError(`Parent folder not found: ${parent}`, 400);
  }
  if (!info.isDirectory()) {
    throw new CloneError(`Parent path is not a folder: ${parent}`, 400);
  }

  await runGitClone(repository.url, destination);

  const directory = await realpath(destination).catch(() => destination);
  return {
    directory,
    name: basename(destination),
    url: repository.url,
  };
}

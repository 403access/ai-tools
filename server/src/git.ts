import { existsSync } from "node:fs";
import { stat } from "node:fs/promises";
import { resolve } from "node:path";
import { runGit } from "./files.ts";
import type {
  GitBranch,
  GitCommit,
  GitPerson,
  GitRepository,
  GitRepositorySummary,
  SessionGit,
} from "./types.ts";

/**
 * Git metadata for the small commit cards on sessions and the repository graph
 * on projects.
 *
 * The hub runs beside the project, so it reads the work tree directly with
 * plumbing/porcelain commands. Nothing here asks OpenCode, and missing or
 * non-repository folders simply return `null` so the clients can show a normal
 * empty state.
 */

const FIELD = "\x1f";
const RECORD = "\x1e";
const LOG_FORMAT = [
  "%H",
  "%h",
  "%P",
  "%an",
  "%ae",
  "%at",
  "%cn",
  "%ce",
  "%ct",
  "%D",
  "%s",
].join(`%x${FIELD.charCodeAt(0).toString(16)}`) +
  `%x${RECORD.charCodeAt(0).toString(16)}`;

const DEFAULT_COMMIT_LIMIT = 2_000;
const MAX_COMMIT_LIMIT = 20_000;
const GIT_TIMEOUT_MS = 12_000;

function clampLimit(limit: number | undefined): number {
  if (!Number.isFinite(limit)) return DEFAULT_COMMIT_LIMIT;
  return Math.min(Math.max(Math.floor(limit ?? DEFAULT_COMMIT_LIMIT), 1), MAX_COMMIT_LIMIT);
}

function person(name: string, email: string, seconds: string): GitPerson {
  const parsed = Number.parseInt(seconds, 10);
  return {
    name,
    email,
    time: Number.isFinite(parsed) ? parsed * 1_000 : 0,
  };
}

/** Parses the records produced by `LOG_FORMAT`. Exported for the unit tests. */
export function parseGitLog(output: string): GitCommit[] {
  const commits: GitCommit[] = [];
  for (const raw of output.split(RECORD)) {
    const record = raw.replace(/^\n+/, "");
    if (!record) continue;
    const fields = record.split(FIELD);
    if (fields.length < 11) continue;
    const [
      hash,
      shortHash,
      parentList,
      authorName,
      authorEmail,
      authorTime,
      committerName,
      committerEmail,
      committerTime,
      decoration,
      ...subjectParts
    ] = fields;
    if (!hash || !shortHash) continue;

    commits.push({
      hash,
      shortHash,
      parents: parentList ? parentList.split(" ").filter(Boolean) : [],
      author: person(authorName ?? "", authorEmail ?? "", authorTime ?? "0"),
      committer: person(committerName ?? "", committerEmail ?? "", committerTime ?? "0"),
      subject: subjectParts.join(FIELD),
      refs: decoration ? decoration.split(", ").filter(Boolean) : [],
    });
  }
  return commits;
}

/** Parses `for-each-ref` output for local branches. Exported for tests. */
export function parseGitBranches(output: string, current: string | null): GitBranch[] {
  const branches: GitBranch[] = [];
  for (const line of output.split("\n")) {
    if (!line.trim()) continue;
    const [name, hash, upstream, track] = line.split(FIELD);
    if (!name || !hash) continue;
    const ahead = Number.parseInt(/ahead (\d+)/.exec(track ?? "")?.[1] ?? "0", 10);
    const behind = Number.parseInt(/behind (\d+)/.exec(track ?? "")?.[1] ?? "0", 10);
    branches.push({
      name,
      hash,
      current: name === current,
      ...(upstream ? { upstream } : {}),
      ahead: Number.isFinite(ahead) ? ahead : 0,
      behind: Number.isFinite(behind) ? behind : 0,
    });
  }
  return branches;
}

function logArgs(limit: number, since?: number, until?: number): string[] {
  const args = [
    "-c",
    "log.showSignature=false",
    "log",
    "--all",
    "--date-order",
    `--max-count=${limit}`,
    `--pretty=format:${LOG_FORMAT}`,
  ];
  if (since !== undefined && Number.isFinite(since) && since > 0) {
    args.push(`--since=@${Math.floor(since / 1_000)}`);
  }
  if (until !== undefined && Number.isFinite(until) && until > 0) {
    args.push(`--until=@${Math.ceil(until / 1_000)}`);
  }
  return args;
}

async function readCommit(directory: string, hash: string): Promise<GitCommit | null> {
  const output = await runGit(
    directory,
    [
      "-c",
      "log.showSignature=false",
      "show",
      "-s",
      `--format=${LOG_FORMAT}`,
      hash,
    ],
    GIT_TIMEOUT_MS,
  );
  return output ? parseGitLog(output)[0] ?? null : null;
}

function countStatusFiles(status: string | null): number {
  if (!status) return 0;
  return status
    .split("\0")
    .filter((entry) => entry.length >= 3)
    .length;
}

/** Common branch/HEAD/working-tree state shared by session and project cards. */
export async function readRepositorySummary(
  directory: string,
): Promise<GitRepositorySummary | null> {
  const raw = directory?.trim();
  if (!raw || !existsSync(raw)) return null;

  let info;
  try {
    info = await stat(raw);
  } catch {
    return null;
  }
  if (!info.isDirectory()) return null;

  const inside = await runGit(raw, ["rev-parse", "--is-inside-work-tree"], GIT_TIMEOUT_MS);
  if (inside?.trim() !== "true") return null;

  const [rootOutput, branchOutput, headOutput, status, upstreamOutput] = await Promise.all([
    runGit(raw, ["rev-parse", "--show-toplevel"], GIT_TIMEOUT_MS),
    runGit(raw, ["symbolic-ref", "--short", "-q", "HEAD"], GIT_TIMEOUT_MS),
    runGit(raw, ["rev-parse", "--verify", "HEAD"], GIT_TIMEOUT_MS),
    runGit(
      raw,
      [
        "status",
        "--porcelain=v1",
        "-z",
        "--untracked-files=all",
        "--no-renames",
      ],
      GIT_TIMEOUT_MS,
    ),
    runGit(
      raw,
      ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
      GIT_TIMEOUT_MS,
    ),
  ]);

  const root = rootOutput?.trim();
  if (!root) return null;

  const branch = branchOutput?.trim() || null;
  const headHash = headOutput?.trim() || null;

  let ahead = 0;
  let behind = 0;
  if (branch && upstreamOutput?.trim()) {
    // Left is upstream-only (behind), right is HEAD-only (ahead).
    const counts = await runGit(
      root,
      ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
      GIT_TIMEOUT_MS,
    );
    const [behindText, aheadText] = (counts ?? "").trim().split(/\s+/);
    ahead = Number.parseInt(aheadText ?? "0", 10) || 0;
    behind = Number.parseInt(behindText ?? "0", 10) || 0;
  }

  const head = headHash ? await readCommit(root, headHash) : null;

  return {
    root,
    branch,
    head,
    dirty: countStatusFiles(status),
    ahead,
    behind,
  };
}

/** Full repository graph: branches, tags, and every reachable commit. */
export async function readProjectGit(
  directory: string,
  limit = DEFAULT_COMMIT_LIMIT,
): Promise<GitRepository | null> {
  const summary = await readRepositorySummary(directory);
  if (!summary) return null;

  const clamped = clampLimit(limit);
  const [branchesOutput, tagsOutput, logOutput, totalOutput] = await Promise.all([
    runGit(
      summary.root,
      [
        "for-each-ref",
        "--sort=-committerdate",
        `--format=%(refname:short)${FIELD}%(objectname)${FIELD}%(upstream:short)${FIELD}%(upstream:track)`,
        "refs/heads",
      ],
      GIT_TIMEOUT_MS,
    ),
    runGit(
      summary.root,
      ["tag", "--list", "--sort=-creatordate"],
      GIT_TIMEOUT_MS,
    ),
    runGit(summary.root, logArgs(clamped), GIT_TIMEOUT_MS),
    runGit(summary.root, ["rev-list", "--all", "--count"], GIT_TIMEOUT_MS),
  ]);

  const commits = parseGitLog(logOutput ?? "");
  const total = Number.parseInt(totalOutput?.trim() ?? "", 10) || commits.length;

  return {
    ...summary,
    branches: parseGitBranches(branchesOutput ?? "", summary.branch),
    tags: (tagsOutput ?? "")
      .split("\n")
      .map((tag) => tag.trim())
      .filter(Boolean),
    commits,
    total,
    truncated: commits.length < total,
  };
}

/** Commit information for one session, including commits made while it ran. */
export async function readSessionGit(
  directory: string | null | undefined,
  created: number | undefined,
  updated: number | undefined,
  limit = DEFAULT_COMMIT_LIMIT,
): Promise<SessionGit> {
  const raw = directory?.trim() || null;
  if (!raw) return { directory: null, repository: null, commits: [], total: 0 };

  const summary = await readRepositorySummary(raw);
  if (!summary) {
    return { directory: raw, repository: null, commits: [], total: 0 };
  }

  // Sessions can be created and updated in either order while a turn is
  // starting, so normalise the window before handing it to git.
  const first = Math.min(created ?? 0, updated ?? 0) || created || updated || 0;
  const last = Math.max(created ?? 0, updated ?? 0) || first;
  const since = first > 0 ? first : undefined;
  const until = last > 0 ? last : undefined;

  const clamped = clampLimit(limit);
  const args = logArgs(clamped, since, until);
  const [logOutput, totalOutput] = await Promise.all([
    runGit(summary.root, args, GIT_TIMEOUT_MS),
    runGit(
      summary.root,
      [
        "rev-list",
        "--all",
        "--count",
        ...(since ? [`--since=@${Math.floor(since / 1_000)}`] : []),
        ...(until ? [`--until=@${Math.ceil(until / 1_000)}`] : []),
      ],
      GIT_TIMEOUT_MS,
    ),
  ]);

  const commits = parseGitLog(logOutput ?? "");
  const total = Number.parseInt(totalOutput?.trim() ?? "", 10) || commits.length;

  return {
    directory: raw,
    repository: summary,
    commits,
    total,
  };
}

import { execFile } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { runGit } from "./files.ts";
import type {
  GitHubCheck,
  GitHubCheckAnnotation,
  GitHubFlowCommit,
  GitHubFlowJob,
  GitHubFlowRepository,
  GitHubFlowRun,
  GitHubFlowRunDetail,
  GitHubFlowStage,
  GitHubFlowStatus,
  GitHubFlowStep,
  GitHubFlows,
} from "./types.ts";

/**
 * GitHub Actions data for the project's Flows tab.
 *
 * The project's `origin` remote identifies the repository. Reads prefer a
 * token from the environment (or the GitHub CLI's stored login) so private
 * repositories work, and fall back to anonymous requests for public ones.
 * Everything is normalized into the small status vocabulary the clients use,
 * and the `needs` graph in the workflow file becomes pipeline stages.
 */

const API_VERSION = "2022-11-28";
const USER_AGENT = "OpenCodeBar-Hub";
const RUN_LIMIT = 20;
const CACHE_MS = 20_000;
const REQUEST_TIMEOUT_MS = 15_000;

export class GitHubError extends Error {
  status: number;

  constructor(message: string, status = 502) {
    super(message);
    this.name = "GitHubError";
    this.status = status;
  }
}

export interface GitHubRemote {
  owner: string;
  repo: string;
  url: string;
  remote: string;
}

export interface ProjectFlowsOptions {
  /** Select a specific run; defaults to the newest run on any branch. */
  runID?: number;
  /** Skip the short in-memory cache. */
  force?: boolean;
}

interface CacheEntry {
  at: number;
  data: GitHubFlows;
}

const cache = new Map<string, CacheEntry>();

/** Clears the short-lived flow cache (used by tests and manual refreshes). */
export function clearGitHubFlowsCache(): void {
  cache.clear();
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function array(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function optionalText(value: unknown): string | undefined {
  const valueText = text(value).trim();
  return valueText ? valueText : undefined;
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() && Number.isFinite(Number(value))) {
    return Number(value);
  }
  return undefined;
}

/** ISO timestamps from GitHub become milliseconds since the epoch. */
function timeValue(value: unknown): number | undefined {
  const source = text(value);
  if (!source) return undefined;
  const parsed = Date.parse(source);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function firstLine(value: string): string {
  return value.split("\n").find((line) => line.trim())?.trim() ?? "";
}

/**
 * Extracts `owner/repo` from the remote forms git accepts for GitHub:
 * https, ssh, scp-style, and the `github.com/owner/repo` shorthand.
 */
export function parseGitHubRemote(raw: string): GitHubRemote | null {
  const value = raw.trim();
  if (!value) return null;
  const match =
    /^(?:(?:https?|ssh|git):\/\/)?(?:[^@/\s]+@)?(?:www\.)?github\.com[/:]([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+?)(?:\.git)?\/?$/i.exec(
      value,
    );
  if (!match) return null;
  const owner = match[1];
  const repo = match[2];
  if (!owner || !repo || repo === "." || repo === "..") return null;
  return {
    owner,
    repo,
    url: `https://github.com/${owner}/${repo}`,
    remote: value,
  };
}

async function readRemote(directory: string, name: string): Promise<string | null> {
  const output = await runGit(directory, ["remote", "get-url", name], 4_000);
  return output?.trim() || null;
}

/** Finds the GitHub repository behind a project directory, if there is one. */
export async function resolveGitHubRemote(directory: string): Promise<GitHubRemote | null> {
  const origin = await readRemote(directory, "origin");
  const originRemote = origin ? parseGitHubRemote(origin) : null;
  if (originRemote) return originRemote;

  const remotes = await runGit(directory, ["remote"], 4_000);
  const names = (remotes ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter((name) => name && name !== "origin");
  for (const name of names) {
    const url = await readRemote(directory, name);
    const parsed = url ? parseGitHubRemote(url) : null;
    if (parsed) return parsed;
  }
  return null;
}

let tokenCache: { at: number; value: string | undefined } | null = null;

function ghCLIToken(): Promise<string | undefined> {
  return new Promise((resolve) => {
    execFile(
      "gh",
      ["auth", "token"],
      { timeout: 4_000, encoding: "utf8" },
      (error, stdout) => {
        if (error) resolve(undefined);
        else resolve(stdout.trim() || undefined);
      },
    );
  });
}

function storedGitHubCLIToken(): string | undefined {
  try {
    const hosts = join(homedir(), ".config", "gh", "hosts.yml");
    if (!existsSync(hosts)) return undefined;
    const contents = readFileSync(hosts, "utf8");
    return /^\s*oauth_token:\s*(\S+)\s*$/m.exec(contents)?.[1];
  } catch {
    return undefined;
  }
}

async function resolveToken(): Promise<string | undefined> {
  if (tokenCache && Date.now() - tokenCache.at < 60_000) return tokenCache.value;

  const value =
    process.env.GITHUB_TOKEN?.trim() ||
    process.env.GH_TOKEN?.trim() ||
    storedGitHubCLIToken() ||
    (await ghCLIToken());

  tokenCache = { at: Date.now(), value };
  return value;
}

function apiRoot(): string {
  return (process.env.GITHUB_API_URL?.trim() || "https://api.github.com").replace(/\/+$/, "");
}

async function githubRequest<T>(path: string, options: { optional?: boolean } = {}): Promise<T | null> {
  const token = await resolveToken();
  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": API_VERSION,
    "User-Agent": USER_AGENT,
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  let response: Response;
  try {
    response = await fetch(`${apiRoot()}${path}`, {
      headers,
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  } catch (caught) {
    if (options.optional) return null;
    throw new GitHubError(
      caught instanceof Error ? `GitHub request failed: ${caught.message}` : "GitHub request failed",
    );
  }

  if (!response.ok) {
    if (options.optional) return null;
    const body = record(await response.json().catch(() => null));
    const detail = text(body.message) || response.statusText || "GitHub request failed";
    const remaining = response.headers.get("x-ratelimit-remaining");
    const reset = numberValue(response.headers.get("x-ratelimit-reset"));
    if (response.status === 401) {
      throw new GitHubError(
        "GitHub rejected the token. Set GITHUB_TOKEN or sign in with `gh auth login`.",
        401,
      );
    }
    if ((response.status === 403 || response.status === 429) && remaining === "0") {
      const when = reset ? new Date(reset * 1_000).toLocaleTimeString() : "later";
      throw new GitHubError(`GitHub API rate limit reached; try again at ${when}.`, 429);
    }
    if (response.status === 404 && !token) {
      throw new GitHubError(
        "GitHub could not find this repository. It may be private: set GITHUB_TOKEN or run `gh auth login`.",
        404,
      );
    }
    if (response.status === 404) {
      throw new GitHubError("GitHub could not find this repository or run.", 404);
    }
    throw new GitHubError(detail, response.status >= 500 ? 502 : 400);
  }

  return (await response.json()) as T;
}

function normalizeStatus(status: unknown, conclusion: unknown): GitHubFlowStatus {
  const rawStatus = text(status).toLowerCase();
  const rawConclusion = text(conclusion).toLowerCase();
  if (rawStatus === "in_progress" || rawStatus === "running") return "running";
  if (rawStatus === "queued" || rawStatus === "requested") return "queued";
  if (rawStatus === "waiting" || rawStatus === "pending") return "waiting";
  switch (rawConclusion) {
    case "success":
      return "success";
    case "failure":
    case "startup_failure":
    case "timed_out":
    case "action_required":
      return "failure";
    case "cancelled":
      return "cancelled";
    case "skipped":
      return "skipped";
    case "neutral":
    case "stale":
      return "neutral";
    default:
      break;
  }
  if (rawConclusion === "success") return "success";
  return "unknown";
}

function durationBetween(start?: number, end?: number, running = false): number {
  if (!start) return 0;
  const finish = end ?? (running ? Date.now() : undefined);
  if (!finish || finish < start) return 0;
  return finish - start;
}

function mapRun(rawValue: unknown): GitHubFlowRun {
  const raw = record(rawValue);
  const headCommit = record(raw.head_commit);
  const user = record(raw.actor ?? raw.triggering_actor);
  const status = normalizeStatus(raw.status, raw.conclusion);
  const createdAt = timeValue(raw.created_at) ?? 0;
  const startedAt = timeValue(raw.run_started_at) ?? timeValue(raw.created_at);
  const updatedAt = timeValue(raw.updated_at);
  const title =
    optionalText(raw.display_title) ??
    optionalText(firstLine(text(headCommit.message))) ??
    optionalText(raw.name) ??
    "Workflow run";

  return {
    id: numberValue(raw.id) ?? 0,
    runNumber: numberValue(raw.run_number) ?? 0,
    attempt: numberValue(raw.run_attempt) ?? 1,
    workflowID: numberValue(raw.workflow_id) ?? 0,
    workflowName: optionalText(raw.name) ?? "GitHub Actions",
    workflowPath: optionalText(raw.path),
    event: optionalText(raw.event) ?? "workflow_dispatch",
    status,
    ...(optionalText(raw.conclusion) ? { conclusion: text(raw.conclusion) } : {}),
    branch: optionalText(raw.head_branch) ?? "",
    sha: optionalText(raw.head_sha) ?? "",
    shortSHA: (optionalText(raw.head_sha) ?? "").slice(0, 7),
    title,
    ...(optionalText(headCommit.message) ? { message: text(headCommit.message) } : {}),
    ...(optionalText(user.login)
      ? {
          actor: {
            login: text(user.login),
            ...(optionalText(user.avatar_url) ? { avatarURL: text(user.avatar_url) } : {}),
          },
        }
      : {}),
    createdAt,
    ...(startedAt !== undefined ? { startedAt } : {}),
    ...(updatedAt !== undefined ? { updatedAt } : {}),
    durationMs: durationBetween(startedAt, updatedAt, status === "running" || status === "queued"),
    htmlURL: optionalText(raw.html_url) ?? "",
  };
}

function mapStep(rawValue: unknown): GitHubFlowStep {
  const raw = record(rawValue);
  const status = normalizeStatus(raw.status, raw.conclusion);
  const startedAt = timeValue(raw.started_at);
  const completedAt = timeValue(raw.completed_at);
  return {
    number: numberValue(raw.number) ?? 0,
    name: optionalText(raw.name) ?? "Step",
    status,
    ...(optionalText(raw.conclusion) ? { conclusion: text(raw.conclusion) } : {}),
    ...(startedAt !== undefined ? { startedAt } : {}),
    ...(completedAt !== undefined ? { completedAt } : {}),
    durationMs: durationBetween(startedAt, completedAt, status === "running"),
  };
}

function mapJob(rawValue: unknown, stage: number): GitHubFlowJob {
  const raw = record(rawValue);
  const status = normalizeStatus(raw.status, raw.conclusion);
  const startedAt = timeValue(raw.started_at);
  const completedAt = timeValue(raw.completed_at);
  return {
    id: numberValue(raw.id) ?? 0,
    name: optionalText(raw.name) ?? "Job",
    status,
    ...(optionalText(raw.conclusion) ? { conclusion: text(raw.conclusion) } : {}),
    ...(startedAt !== undefined ? { startedAt } : {}),
    ...(completedAt !== undefined ? { completedAt } : {}),
    durationMs: durationBetween(startedAt, completedAt, status === "running"),
    ...(optionalText(raw.runner_name) ? { runnerName: text(raw.runner_name) } : {}),
    labels: array(raw.labels).map((label) => text(label)).filter(Boolean),
    htmlURL: optionalText(raw.html_url) ?? "",
    stage,
    steps: array(raw.steps).map(mapStep),
  };
}

function mapCheckAnnotation(rawValue: unknown): GitHubCheckAnnotation {
  const raw = record(rawValue);
  const level = optionalText(raw.annotation_level);
  return {
    path: optionalText(raw.path) ?? "",
    startLine: numberValue(raw.start_line) ?? 0,
    endLine: numberValue(raw.end_line) ?? 0,
    level: level === "warning" || level === "failure" ? level : "notice",
    ...(optionalText(raw.title) ? { title: text(raw.title) } : {}),
    message: optionalText(raw.message) ?? "",
  };
}

function mapCheck(rawValue: unknown, annotations: GitHubCheckAnnotation[]): GitHubCheck {
  const raw = record(rawValue);
  const status = normalizeStatus(raw.status, raw.conclusion);
  const startedAt = timeValue(raw.started_at);
  const completedAt = timeValue(raw.completed_at);
  const output = record(raw.output);
  const app = record(raw.app);
  return {
    id: numberValue(raw.id) ?? 0,
    name: optionalText(raw.name) ?? "Check",
    status,
    ...(optionalText(raw.conclusion) ? { conclusion: text(raw.conclusion) } : {}),
    ...(startedAt !== undefined ? { startedAt } : {}),
    ...(completedAt !== undefined ? { completedAt } : {}),
    durationMs: durationBetween(startedAt, completedAt, status === "running"),
    ...(optionalText(raw.details_url) ? { detailsURL: text(raw.details_url) } : {}),
    ...(optionalText(output.title) ? { description: text(output.title) } : {}),
    ...(optionalText(output.summary) ? { summary: text(output.summary) } : {}),
    ...(optionalText(app.name) ? { appName: text(app.name) } : {}),
    annotations,
  };
}

function mapCommit(rawValue: unknown): GitHubFlowCommit | null {
  const raw = record(rawValue);
  const commit = record(raw.commit);
  const author = record(raw.author);
  const sha = optionalText(raw.sha);
  if (!sha) return null;
  const stats = record(raw.stats);
  return {
    sha,
    shortSHA: sha.slice(0, 7),
    message: optionalText(commit.message) ?? "",
    authorName: optionalText(record(commit.author).name) ?? optionalText(author.login) ?? "",
    ...(optionalText(author.login) ? { authorLogin: text(author.login) } : {}),
    additions: numberValue(stats.additions) ?? 0,
    deletions: numberValue(stats.deletions) ?? 0,
    changedFiles: numberValue(stats.total) ?? 0,
    url: optionalText(raw.html_url) ?? "",
  };
}

// MARK: - Workflow needs

export interface WorkflowJobDefinition {
  id: string;
  name?: string;
  needs: string[];
}

function leadingSpaces(line: string): number {
  return /^\s*/.exec(line)?.[0].replace(/\t/g, "  ").length ?? 0;
}

function stripYamlComment(line: string): string {
  let quote: string | null = null;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (quote) {
      if (char === quote) quote = null;
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "#") {
      return line.slice(0, index);
    }
  }
  return line;
}

function parseNeedsValue(value: string): string[] {
  const trimmed = value.trim();
  if (!trimmed) return [];
  if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
    return trimmed
      .slice(1, -1)
      .split(",")
      .map((entry) => entry.trim().replace(/^['"]|['"]$/g, ""))
      .filter(Boolean);
  }
  return [trimmed.replace(/^['"]|['"]$/g, "")];
}

/**
 * Reads the job ids and their `needs` lists from a GitHub Actions workflow.
 * This intentionally understands only the small YAML subset those two fields
 * use, so the hub does not need a YAML dependency just to draw stages.
 */
export function parseWorkflowJobs(yaml: string): WorkflowJobDefinition[] {
  const lines = yaml.split(/\r?\n/);
  const jobs: WorkflowJobDefinition[] = [];
  let jobsIndent: number | null = null;
  let jobIndent: number | null = null;
  let current: WorkflowJobDefinition | null = null;
  let needsIndent: number | null = null;

  const flush = () => {
    if (current) jobs.push(current);
    current = null;
    needsIndent = null;
  };

  for (const original of lines) {
    const line = stripYamlComment(original).replace(/\s+$/, "");
    if (!line.trim()) continue;
    const indent = leadingSpaces(line);
    const trimmed = line.trim();

    if (jobsIndent === null) {
      if (indent === 0 && /^jobs:\s*$/.test(trimmed)) jobsIndent = indent;
      continue;
    }

    if (indent <= jobsIndent && !trimmed.startsWith("-")) {
      flush();
      jobsIndent = null;
      jobIndent = null;
      continue;
    }

    if (jobIndent === null) {
      if (trimmed.startsWith("-")) continue;
      const match = /^([A-Za-z0-9_.-]+):\s*$/.exec(trimmed);
      if (match?.[1]) {
        jobIndent = indent;
        current = { id: match[1], needs: [] };
      }
      continue;
    }

    if (indent === jobIndent && !trimmed.startsWith("-")) {
      flush();
      const match = /^([A-Za-z0-9_.-]+):\s*$/.exec(trimmed);
      if (match?.[1]) {
        current = { id: match[1], needs: [] };
      }
      continue;
    }

    if (!current) continue;

    if (needsIndent !== null) {
      if (indent <= needsIndent && !trimmed.startsWith("-")) {
        needsIndent = null;
      } else {
        if (trimmed.startsWith("-")) {
          const need = trimmed.slice(1).trim().replace(/^['"]|['"]$/g, "");
          if (need) current.needs.push(need);
        }
        continue;
      }
    }

    if (indent === jobIndent + 2) {
      const nameMatch = /^name:\s*(.+)$/.exec(trimmed);
      if (nameMatch?.[1]) {
        const name = nameMatch[1].trim().replace(/^['"]|['"]$/g, "");
        if (name) current.name = name;
      }
      const needsMatch = /^needs:\s*(.*)$/.exec(trimmed);
      if (needsMatch) {
        const values = parseNeedsValue(needsMatch[1] ?? "");
        if (values.length > 0) current.needs.push(...values);
        else needsIndent = indent;
      }
    }
  }

  flush();
  return jobs;
}

function normalizeJobName(value: string): string {
  return value
    .replace(/\$\{\{[^}]*\}\}/g, " ")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

function workflowJobFor(
  apiName: string,
  definitions: WorkflowJobDefinition[],
): WorkflowJobDefinition | undefined {
  const normalized = normalizeJobName(apiName);
  const matrixBase = normalizeJobName(apiName.replace(/\s*\([^)]*\)\s*$/, ""));
  for (const definition of definitions) {
    const candidates = [definition.id, definition.name ?? ""]
      .map(normalizeJobName)
      .filter(Boolean);
    if (candidates.some((candidate) => candidate === normalized || candidate === matrixBase)) {
      return definition;
    }
  }
  return undefined;
}

function dependencyDepth(
  id: string,
  definitions: Map<string, WorkflowJobDefinition>,
  seen = new Set<string>(),
): number {
  if (seen.has(id)) return 0;
  const definition = definitions.get(id);
  if (!definition || definition.needs.length === 0) return 0;
  const nextSeen = new Set(seen);
  nextSeen.add(id);
  return definition.needs.reduce(
    (max, need) => Math.max(max, dependencyDepth(need, definitions, nextSeen) + 1),
    0,
  );
}

function stageStatus(jobs: GitHubFlowJob[]): GitHubFlowStatus {
  if (jobs.some((job) => job.status === "failure")) return "failure";
  if (jobs.some((job) => job.status === "running")) return "running";
  if (jobs.some((job) => job.status === "queued" || job.status === "waiting")) return "queued";
  if (jobs.length > 0 && jobs.every((job) => job.status === "success")) return "success";
  if (jobs.some((job) => job.status === "cancelled")) return "cancelled";
  if (jobs.length > 0 && jobs.every((job) => job.status === "skipped")) return "skipped";
  return "neutral";
}

/** Turns `build-and-test` into `Build-and-test` for stage headings. */
function titleCase(value: string): string {
  if (!value) return value;
  return value[0]!.toUpperCase() + value.slice(1);
}

/** Groups jobs by dependency depth so the board reads as a pipeline. */
export function groupJobsIntoStages(
  jobs: GitHubFlowJob[],
  definitions: WorkflowJobDefinition[],
): GitHubFlowStage[] {
  const definitionsByID = new Map(definitions.map((definition) => [definition.id, definition]));
  const grouped = new Map<number, GitHubFlowJob[]>();
  const definitionsAtStage = new Map<number, Set<string>>();

  for (const job of jobs) {
    const definition = workflowJobFor(job.name, definitions);
    const stage = definition
      ? dependencyDepth(definition.id, definitionsByID)
      : 0;
    grouped.set(stage, [...(grouped.get(stage) ?? []), { ...job, stage }]);
    if (definition) {
      definitionsAtStage.set(stage, (definitionsAtStage.get(stage) ?? new Set()).add(definition.id));
    }
  }

  return [...grouped.entries()]
    .sort(([left], [right]) => left - right)
    .map(([index, stageJobs]) => {
      const stageDefinitions = [...(definitionsAtStage.get(index) ?? [])];
      const singleDefinition = stageDefinitions.length === 1
        ? definitionsByID.get(stageDefinitions[0]!)
        : undefined;
      const name = singleDefinition
        ? singleDefinition.name ?? titleCase(singleDefinition.id)
        : stageJobs.length === 1
          ? stageJobs[0]?.name ?? `Stage ${index + 1}`
          : `Stage ${index + 1}`;
      return {
        index,
        name,
        status: stageStatus(stageJobs),
        jobs: stageJobs,
      };
    });
}

// MARK: - Reads

function repoPath(remote: GitHubRemote): string {
  return `/repos/${encodeURIComponent(remote.owner)}/${encodeURIComponent(remote.repo)}`;
}

async function readWorkflowDefinitions(
  repositoryPath: string,
  path: string | undefined,
  sha: string,
): Promise<WorkflowJobDefinition[]> {
  if (!path) return [];
  const encodedPath = path
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  const contents = await githubRequest<{ content?: string; encoding?: string }>(
    `${repositoryPath}/contents/${encodedPath}?ref=${encodeURIComponent(sha)}`,
    { optional: true },
  );
  if (!contents || contents.encoding !== "base64" || !contents.content) return [];
  try {
    const yaml = Buffer.from(contents.content, "base64").toString("utf8");
    return parseWorkflowJobs(yaml);
  } catch {
    return [];
  }
}

async function readChecks(
  repositoryPath: string,
  sha: string,
): Promise<GitHubCheck[]> {
  if (!sha) return [];
  const response = await githubRequest<{ check_runs?: unknown[] }>(
    `${repositoryPath}/commits/${encodeURIComponent(sha)}/check-runs?per_page=100&filter=latest`,
    { optional: true },
  );
  if (!response) return [];
  const checks = array(response.check_runs);
  const mapped = await Promise.all(
    checks.slice(0, 100).map(async (entry) => {
      const raw = record(entry);
      const annotationsCount = numberValue(record(raw.output).annotations_count) ?? 0;
      let annotations: GitHubCheckAnnotation[] = [];
      if (annotationsCount > 0) {
        const id = numberValue(raw.id);
        if (id !== undefined) {
          const annotationResponse = await githubRequest<unknown[]>(
            `${repositoryPath}/check-runs/${id}/annotations?per_page=50`,
            { optional: true },
          );
          annotations = array(annotationResponse).map(mapCheckAnnotation);
        }
      }
      return mapCheck(entry, annotations);
    }),
  );
  return mapped;
}

async function readRunDetail(
  repositoryPath: string,
  run: GitHubFlowRun,
): Promise<GitHubFlowRunDetail> {
  const [jobsResponse, definitions, checks] = await Promise.all([
    githubRequest<{ jobs?: unknown[] }>(
      `${repositoryPath}/actions/runs/${run.id}/jobs?per_page=100&filter=latest`,
      { optional: true },
    ),
    readWorkflowDefinitions(repositoryPath, run.workflowPath, run.sha),
    readChecks(repositoryPath, run.sha),
  ]);

  const rawJobs = array(jobsResponse?.jobs);
  const preliminary = rawJobs.map((job) => mapJob(job, 0));
  const stages = groupJobsIntoStages(preliminary, definitions);
  const jobs = stages.flatMap((stage) => stage.jobs).sort((left, right) => {
    if (left.stage !== right.stage) return left.stage - right.stage;
    return (left.startedAt ?? 0) - (right.startedAt ?? 0);
  });

  return {
    ...run,
    jobs,
    stages,
    checks,
  };
}

async function readFlows(
  remote: GitHubRemote,
  options: ProjectFlowsOptions,
): Promise<GitHubFlows> {
  const repositoryPath = repoPath(remote);
  const runsResponse = await githubRequest<{ workflow_runs?: unknown[] }>(
    `${repositoryPath}/actions/runs?per_page=${RUN_LIMIT}`,
  );
  const runs = array(runsResponse?.workflow_runs).map(mapRun);
  let selected: GitHubFlowRun | undefined;

  if (options.runID !== undefined) {
    const runResponse = await githubRequest<unknown>(
      `${repositoryPath}/actions/runs/${options.runID}`,
      { optional: true },
    );
    if (runResponse) selected = mapRun(runResponse);
  }
  selected ??= runs[0];
  if (!selected) {
    return {
      repository: {
        owner: remote.owner,
        name: remote.repo,
        url: remote.url,
        remote: remote.remote,
      },
      branch: null,
      runs,
      run: null,
      commit: null,
      generatedAt: Date.now(),
    };
  }

  const [detail, commit] = await Promise.all([
    readRunDetail(repositoryPath, selected),
    githubRequest<unknown>(`${repositoryPath}/commits/${encodeURIComponent(selected.sha)}`, {
      optional: true,
    }),
  ]);

  return {
    repository: {
      owner: remote.owner,
      name: remote.repo,
      url: remote.url,
      remote: remote.remote,
    },
    branch: selected.branch || null,
    runs,
    run: detail,
    commit: mapCommit(commit),
    generatedAt: Date.now(),
  };
}

/**
 * Reads the GitHub Actions flows for one project. Returns null when the
 * project's remotes do not point at GitHub.
 */
export async function readProjectFlows(
  directory: string,
  options: ProjectFlowsOptions = {},
): Promise<GitHubFlows | null> {
  const remote = await resolveGitHubRemote(directory);
  if (!remote) return null;

  const key = `${remote.owner}/${remote.repo}:${options.runID ?? "latest"}`;
  const cached = cache.get(key);
  if (!options.force && cached && Date.now() - cached.at < CACHE_MS) {
    return cached.data;
  }

  const data = await readFlows(remote, options);
  cache.set(key, { at: Date.now(), data });
  return data;
}

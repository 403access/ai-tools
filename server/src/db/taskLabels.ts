import type { SessionTask, TaskLabel, TaskLabelKind, TaskStatus } from "../types.ts";

/**
 * Deterministic, dependency-free task classification.
 *
 * A session title is usually a one-line summary of the user's request, and the
 * hub also remembers the first prompt that was sent through it. That is enough
 * signal to label a task without asking a model. Labels are intentionally few:
 * one type, at most one scope, and at most one risk. More than that turns the
 * board into noise and makes the automatic guesses feel authoritative when
 * they are only hints.
 */

interface Rule<T extends string> {
  id: T;
  title: string;
  keywords: string[];
}

const TYPE_RULES: Array<Rule<TaskType>> = [
  {
    id: "security",
    title: "Security",
    keywords: [
      "security",
      "vulnerability",
      "vulnerabilities",
      "cve",
      "exploit",
      "auth",
      "authentication",
      "authorization",
      "permission",
      "permissions",
      "secret",
      "secrets",
      "token leak",
      "csrf",
      "xss",
      "sql injection",
      "sanitize",
      "encryption",
      "privacy",
    ],
  },
  {
    id: "bug",
    title: "Bug",
    keywords: [
      "bug",
      "bugs",
      "fix",
      "fixed",
      "broken",
      "break",
      "breaks",
      "crash",
      "crashes",
      "crashing",
      "error",
      "errors",
      "failing",
      "fails",
      "failed",
      "failure",
      "regression",
      "defect",
      "wrong",
      "incorrect",
      "exception",
      "panic",
      "does not work",
      "doesn't work",
      "not working",
      "unexpected",
      "issue",
    ],
  },
  {
    id: "performance",
    title: "Performance",
    keywords: [
      "performance",
      "slow",
      "slowly",
      "slowness",
      "optimize",
      "optimise",
      "latency",
      "speed up",
      "faster",
      "bottleneck",
      "memory usage",
      "cpu usage",
      "jank",
    ],
  },
  {
    id: "feature",
    title: "Feature",
    keywords: [
      "add",
      "adds",
      "implement",
      "introduce",
      "support",
      "allow",
      "enable",
      "feature",
      "new",
      "build",
      "create",
      "make it possible",
      "ability to",
    ],
  },
  {
    id: "refactor",
    title: "Refactor",
    keywords: [
      "refactor",
      "refactoring",
      "cleanup",
      "clean up",
      "restructure",
      "extract",
      "simplify",
      "dedupe",
      "rename",
      "split",
      "reorganize",
      "reorganise",
      "remove dead",
    ],
  },
  {
    id: "tests",
    title: "Tests",
    keywords: ["test", "tests", "testing", "coverage", "flaky", "e2e", "integration test", "unit test"],
  },
  {
    id: "docs",
    title: "Docs",
    keywords: ["docs", "documentation", "readme", "guide", "changelog", "docstring", "comments"],
  },
  {
    id: "chore",
    title: "Chore",
    keywords: [
      "chore",
      "bump",
      "upgrade",
      "dependency",
      "dependencies",
      "deps",
      "release",
      "ci",
      "build",
      "lint",
      "format",
      "version",
    ],
  },
  {
    id: "question",
    title: "Question",
    keywords: ["how do", "how does", "why does", "what is", "explain", "investigate", "can you"],
  },
];

const SCOPE_RULES: Array<Rule<TaskScope>> = [
  {
    id: "infrastructure",
    title: "Infrastructure",
    keywords: [
      "ci",
      "pipeline",
      "deploy",
      "deployment",
      "docker",
      "kubernetes",
      "terraform",
      "infra",
      "infrastructure",
      "nix",
      "nixos",
      "vm",
      "vms",
      "server setup",
      "release process",
    ],
  },
  {
    id: "product",
    title: "Product",
    keywords: [
      "user",
      "users",
      "customer",
      "customers",
      "ui",
      "ux",
      "screen",
      "page",
      "button",
      "dashboard",
      "onboarding",
      "design",
      "notification",
      "search",
      "settings",
      "mobile app",
      "website",
      "workflow",
      "experience",
      "copy",
      "label",
    ],
  },
  {
    id: "technical",
    title: "Technical",
    keywords: [
      "api",
      "endpoint",
      "server",
      "database",
      "db",
      "schema",
      "migration",
      "backend",
      "frontend",
      "refactor",
      "test",
      "tests",
      "ci",
      "build",
      "sdk",
      "cli",
      "library",
      "dependency",
      "dependencies",
      "cache",
      "index",
      "sql",
      "architecture",
      "protocol",
    ],
  },
];

const RISK_RULES: Array<Rule<TaskRisk>> = [
  {
    id: "security-sensitive",
    title: "Security-sensitive",
    keywords: [
      "security",
      "vulnerability",
      "cve",
      "auth",
      "authentication",
      "authorization",
      "secret",
      "secrets",
      "token",
      "password",
      "permission",
      "permissions",
      "encryption",
    ],
  },
  {
    id: "data-loss",
    title: "Data loss",
    keywords: [
      "data loss",
      "delete data",
      "drop table",
      "truncate",
      "destructive",
      "overwrite",
      "wipe",
      "erase",
    ],
  },
  {
    id: "breaking-change",
    title: "Breaking change",
    keywords: [
      "breaking",
      "breaking change",
      "migration",
      "migrate",
      "rename",
      "remove api",
      "deprecate",
      "incompatible",
    ],
  },
];

type TaskType =
  | "bug"
  | "feature"
  | "refactor"
  | "tests"
  | "docs"
  | "performance"
  | "security"
  | "chore"
  | "question";

type TaskScope = "product" | "technical" | "infrastructure";
type TaskRisk = "security-sensitive" | "data-loss" | "breaking-change";

function normalize(value: string | undefined): string {
  return (value ?? "")
    .toLowerCase()
    .replace(/[_/\\]+/g, " ")
    .replace(/[^\p{L}\p{N}+#.-]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function hits(haystack: string, phrase: string): number {
  if (!haystack || !phrase) return 0;
  if (phrase.includes(" ") || phrase.includes("-") || phrase.includes(".")) {
    return haystack.includes(phrase) ? 1 : 0;
  }
  const pattern = new RegExp(`\\b${escapeRegExp(phrase)}\\b`, "g");
  return haystack.match(pattern)?.length ?? 0;
}

function score(title: string, context: string, keywords: string[]): number {
  let total = 0;
  for (const keyword of keywords) {
    // The title is the curated summary, so it counts double.
    total += hits(title, keyword) * 2 + hits(context, keyword);
  }
  return total;
}

function bestRule<T extends string>(
  rules: Array<Rule<T>>,
  title: string,
  context: string,
  minimum: number,
): Rule<T> | null {
  let winner: Rule<T> | null = null;
  let best = 0;
  for (const rule of rules) {
    const value = score(title, context, rule.keywords);
    if (value > best) {
      best = value;
      winner = rule;
    }
  }
  return best >= minimum ? winner : null;
}

function label(id: string, title: string, kind: TaskLabelKind): TaskLabel {
  return { id, title, kind };
}

/** Labels for one task, newest signals first: type, scope, then risk. */
export function classifyTaskLabels(
  titleValue: string | undefined,
  contextValue: string | undefined,
): TaskLabel[] {
  const title = normalize(titleValue);
  const context = normalize(contextValue);
  if (!title && !context) return [];

  const labels: TaskLabel[] = [];
  const type = bestRule(TYPE_RULES, title, context, 2);
  if (type) labels.push(label(type.id, type.title, "type"));

  let scope = bestRule(SCOPE_RULES, title, context, 2);
  // A refactor, test, or docs task is technical even when the prompt does not
  // spell that out. Feature and bug requests can be either, so leave those
  // unlabelled rather than guessing.
  if (!scope && type && ["refactor", "tests", "docs", "chore"].includes(type.id)) {
    scope = { id: "technical", title: "Technical", keywords: [] };
  }
  if (scope) labels.push(label(scope.id, scope.title, "scope"));

  const risk = bestRule(RISK_RULES, title, context, 1);
  // "Security" already says everything the risk label would add.
  if (risk && !(risk.id === "security-sensitive" && type?.id === "security")) {
    labels.push(label(risk.id, risk.title, "risk"));
  }

  return labels;
}

export interface TaskStatusInput {
  active: boolean;
  stored?: string;
  doneAt?: number;
  updated: number;
  queued?: boolean;
}

/**
 * The board state is derived, not stored. A queued task waits for its start
 * time and a free concurrency slot; a running session is always working; a
 * finished one waits for review until the user resolves it. Sending another
 * prompt moves `updated` past `doneAt`, which deliberately reopens the task.
 */
export function deriveTaskStatus(input: TaskStatusInput): TaskStatus {
  if (input.queued) return "queued";
  if (input.active) return "working";
  if (input.stored === "dismissed") return "dismissed";
  if (input.stored === "done" && input.doneAt !== undefined && input.doneAt >= input.updated) {
    return "done";
  }
  return "review";
}

export function buildSessionTask(input: {
  active: boolean;
  stored?: string;
  doneAt?: number;
  createdAt: number;
  updated: number;
  title?: string;
  context?: string;
  queuedAt?: number;
  queuedUntil?: number;
  queuedPrompt?: string;
}): SessionTask {
  const queued =
    input.queuedAt !== undefined || input.queuedPrompt !== undefined;
  const task: SessionTask = {
    status: deriveTaskStatus({ ...input, queued }),
    labels: classifyTaskLabels(input.title, input.context),
    createdAt: input.createdAt,
  };
  if (input.doneAt !== undefined) task.doneAt = input.doneAt;
  if (input.queuedAt !== undefined) task.queuedAt = input.queuedAt;
  if (input.queuedUntil !== undefined) task.queuedUntil = input.queuedUntil;
  if (input.queuedPrompt !== undefined) task.queuedPrompt = input.queuedPrompt;
  return task;
}

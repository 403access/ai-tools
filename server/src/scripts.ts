import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { ProjectScript, ProjectScripts } from "./types.ts";

/**
 * High-level project scripts for the Flows tab.
 *
 * Reads the manifests a project commonly exposes as runnable tasks — package
 * scripts, Makefile targets, just recipes and Composer scripts — and returns a
 * flat list with the command a user would type. Nothing is executed and no
 * nested workspace packages are scanned: this is a quick, root-level view of
 * the handles the project already advertises.
 */

const MAX_PER_SOURCE = 100;
const MAX_SCRIPTS = 300;

function readText(path: string): string | undefined {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return undefined;
  }
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function trimmed(value: unknown): string | undefined {
  const result = text(value).trim();
  return result ? result : undefined;
}

function parseJSON(raw: string | undefined): Record<string, unknown> | undefined {
  if (!raw) return undefined;
  try {
    const value: unknown = JSON.parse(raw);
    return record(value);
  } catch {
    return undefined;
  }
}

export interface ScriptInvocation {
  command: string;
  args: string[];
}

/** The executable and arguments that run one script without a shell. */
function invocationFor(tool: string, name: string): ScriptInvocation | null {
  switch (tool) {
    case "npm":
    case "pnpm":
    case "yarn":
    case "bun":
      return { command: tool, args: ["run", name] };
    case "make":
      return { command: "make", args: [name] };
    case "just":
      return { command: "just", args: [name] };
    case "composer":
      return { command: "composer", args: ["run", name] };
    default:
      return null;
  }
}

function invocationText(tool: string, name: string): string {
  const invocation = invocationFor(tool, name);
  return invocation ? [invocation.command, ...invocation.args].join(" ") : name;
}

/** How the Flows tab runs a discovered script; null for an unknown tool. */
export function scriptInvocation(script: ProjectScript): ScriptInvocation | null {
  return invocationFor(script.tool, script.name);
}

/** Picks the package runner the project already uses. */
function packageRunner(directory: string, manifest: Record<string, unknown>): string {
  const declared = text(manifest.packageManager).split("@")[0]?.trim();
  if (declared === "npm" || declared === "pnpm" || declared === "yarn" || declared === "bun") {
    return declared;
  }
  if (existsSync(join(directory, "bun.lock")) || existsSync(join(directory, "bun.lockb"))) {
    return "bun";
  }
  if (existsSync(join(directory, "pnpm-lock.yaml"))) return "pnpm";
  if (existsSync(join(directory, "yarn.lock"))) return "yarn";
  return "npm";
}

function packageScripts(directory: string): ProjectScript[] {
  const manifest = parseJSON(readText(join(directory, "package.json")));
  if (!manifest) return [];
  const scripts = record(manifest.scripts);
  const tool = packageRunner(directory, manifest);
  return Object.entries(scripts)
    .slice(0, MAX_PER_SOURCE)
    .map(([name, value]) => ({ name, detail: trimmed(value) }))
    .map(({ name, detail }) => ({
      name,
      command: invocationText(tool, name),
      source: "package.json",
      tool,
      ...(detail ? { detail } : {}),
    }));
}

/** Removes trailing `## comment` documentation from a Makefile rule. */
function makeDescription(rest: string): string | undefined {
  const index = rest.indexOf("##");
  if (index < 0) return undefined;
  return trimmed(rest.slice(index + 2));
}

function makeScripts(directory: string): ProjectScript[] {
  const names = ["Makefile", "makefile", "GNUmakefile"];
  const filename = names.find((name) => existsSync(join(directory, name)));
  if (!filename) return [];
  const raw = readText(join(directory, filename));
  if (!raw) return [];

  const scripts: ProjectScript[] = [];
  let pendingComment: string | undefined;

  for (const rawLine of raw.split(/\r?\n/)) {
    const line = rawLine.trimEnd();
    if (!line.trim()) {
      pendingComment = undefined;
      continue;
    }
    if (line.startsWith("\t")) continue;

    if (line.startsWith("#")) {
      const comment = line.replace(/^#+\s?/, "").trim();
      if (comment) pendingComment = pendingComment ? `${pendingComment} ${comment}` : comment;
      continue;
    }

    // `target target2: prerequisites` but not `VAR := value` or `VAR ?= value`.
    const match = /^([A-Za-z0-9_./+-]+(?:\s+[A-Za-z0-9_./+-]+)*)\s*:(?!=)(.*)$/.exec(line);
    if (!match) {
      pendingComment = undefined;
      continue;
    }

    const inline = makeDescription(match[2] ?? "");
    const targets = (match[1] ?? "").split(/\s+/);
    for (const name of targets) {
      if (!name || name.startsWith(".") || name.includes("%")) continue;
      if (scripts.length >= MAX_PER_SOURCE) break;
      const description = inline ?? pendingComment;
      scripts.push({
        name,
        command: invocationText("make", name),
        source: filename,
        tool: "make",
        ...(description ? { description } : {}),
      });
    }
    pendingComment = undefined;
  }

  return scripts;
}

const JUST_RESERVED = new Set([
  "alias",
  "assert",
  "export",
  "import",
  "mod",
  "set",
  "unexport",
]);

function justScripts(directory: string): ProjectScript[] {
  const filename = ["justfile", "Justfile", ".justfile"].find((name) =>
    existsSync(join(directory, name)),
  );
  if (!filename) return [];
  const raw = readText(join(directory, filename));
  if (!raw) return [];

  const scripts: ProjectScript[] = [];
  let pendingComment: string | undefined;

  for (const rawLine of raw.split(/\r?\n/)) {
    const line = rawLine.trimEnd();
    if (!line.trim()) {
      pendingComment = undefined;
      continue;
    }
    if (line.startsWith(" ") || line.startsWith("\t")) continue;

    const trimmedLine = line.trim();
    if (trimmedLine.startsWith("#")) {
      const comment = trimmedLine.replace(/^#+\s?/, "").trim();
      if (comment) pendingComment = pendingComment ? `${pendingComment} ${comment}` : comment;
      continue;
    }

    const match = /^@?([A-Za-z_][A-Za-z0-9_-]*)(?:[ \t][^:\n]*)?:(?!=)/.exec(trimmedLine);
    const recipe = match?.[1];
    if (!recipe || JUST_RESERVED.has(recipe)) {
      pendingComment = undefined;
      continue;
    }
    if (scripts.length >= MAX_PER_SOURCE) break;
    scripts.push({
      name: recipe,
      command: invocationText("just", recipe),
      source: filename,
      tool: "just",
      ...(pendingComment ? { description: pendingComment } : {}),
    });
    pendingComment = undefined;
  }

  return scripts;
}

function composerScripts(directory: string): ProjectScript[] {
  const manifest = parseJSON(readText(join(directory, "composer.json")));
  if (!manifest) return [];
  const scripts = record(manifest.scripts);
  return Object.entries(scripts)
    .slice(0, MAX_PER_SOURCE)
    .map(([name, value]) => ({
      name,
      detail: Array.isArray(value)
        ? value.map(text).filter(Boolean).join(" · ")
        : trimmed(value),
    }))
    .map(({ name, detail }) => ({
      name,
      command: invocationText("composer", name),
      source: "composer.json",
      tool: "composer",
      ...(detail ? { detail } : {}),
    }));
}

/** Reads the project's runnable scripts. Empty when no manifest is present. */
export function readProjectScripts(directory: string): ProjectScripts {
  const seen = new Set<string>();
  const scripts: ProjectScript[] = [];

  for (const script of [
    ...packageScripts(directory),
    ...makeScripts(directory),
    ...justScripts(directory),
    ...composerScripts(directory),
  ]) {
    const key = `${script.tool}:${script.name}`;
    if (seen.has(key)) continue;
    seen.add(key);
    scripts.push(script);
    if (scripts.length >= MAX_SCRIPTS) break;
  }

  return { scripts, generatedAt: Date.now() };
}

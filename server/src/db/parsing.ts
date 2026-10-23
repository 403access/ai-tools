import type { FileDiff } from "../types.ts";
import { number, text } from "./rows.ts";

/**
 * Reads the file changes OpenCode attaches to edit/write tool calls. Edits carry
 * a `state.metadata.files` array of exact patches. Writes only carry the new
 * content, so synthesize a patch from it — otherwise newly created files would
 * be invisible to the Changes views.
 */
export function parseFileDiffs(part: unknown, directory?: string | null): FileDiff[] {
  if (!part || typeof part !== "object") return [];
  const record = part as Record<string, unknown>;
  if (record.type !== "tool") return [];
  const state = record.state;
  if (!state || typeof state !== "object") return [];

  const stateRecord = state as Record<string, unknown>;
  const metadata = stateRecord.metadata;
  if (metadata && typeof metadata === "object") {
    const source = metadata as Record<string, unknown>;
    const files = Array.isArray(source.files) ? source.files : [];
    const diffs: FileDiff[] = [];
    for (const entry of files) {
      if (!entry || typeof entry !== "object") continue;
      const file = entry as Record<string, unknown>;
      const patch = text(file.patch);
      const diff: FileDiff = {
        additions: number(file.additions),
        deletions: number(file.deletions),
      };
      const name = text(file.file);
      if (name) diff.file = name;
      if (patch !== undefined) diff.patch = patch;
      const status = text(file.status);
      if (status === "added" || status === "deleted" || status === "modified") {
        diff.status = status;
      }
      diffs.push(diff);
    }
    if (diffs.length) return diffs;
  }

  // The write tool has no patch metadata; its input holds the full new content.
  const name = text(record.name)?.toLowerCase();
  const input = stateRecord.input;
  if (name === "write" && input && typeof input === "object") {
    const fields = input as Record<string, unknown>;
    const path = text(fields.path) ?? text(fields.filePath);
    const content = text(fields.content);
    if (path && content !== undefined) {
      const file = relativePath(path, directory);
      const lines = content.split("\n");
      if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop();
      const patch = [
        `--- /dev/null`,
        `+++ b/${file}`,
        `@@ -0,0 +1,${lines.length} @@`,
        ...lines.map((line) => `+${line}`),
      ].join("\n");
      return [{ file, patch, additions: lines.length, deletions: 0, status: "added" }];
    }
  }

  return [];
}

function relativePath(path: string, directory?: string | null): string {
  if (!directory) return path;
  const prefix = directory.endsWith("/") ? directory : `${directory}/`;
  return path.startsWith(prefix) ? path.slice(prefix.length) : path;
}

/** Collapses tool statuses into the three buckets the stats UI shows. */
export function toolOutcome(status: unknown): "succeeded" | "failed" | "unfinished" {
  const value = typeof status === "string" ? status.toLowerCase() : "";
  if (value === "completed" || value === "success" || value === "succeeded") return "succeeded";
  if (value === "error" || value === "failed" || value === "failure") return "failed";
  return "unfinished";
}

/** OpenCode reports failures as `{ type, message }` or occasionally a string. */
export function toolErrorText(raw: unknown): string | undefined {
  if (typeof raw === "string") return raw;
  if (!raw || typeof raw !== "object") return undefined;
  const record = raw as Record<string, unknown>;
  if (typeof record.message === "string" && record.message) return record.message;
  try {
    return JSON.stringify(raw).slice(0, 1_000);
  } catch {
    return undefined;
  }
}

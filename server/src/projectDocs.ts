import { readFile } from "node:fs/promises";
import { join } from "node:path";

/**
 * Reads the opening prose from a project's README so a new Docs tab starts
 * with a useful description instead of an empty field. This is only a seed:
 * the user can edit or replace it, and the hub never writes to the project.
 */

const README_CANDIDATES = [
  "README.md",
  "Readme.md",
  "readme.md",
  "README.markdown",
  "README",
];

const MAX_READ_SIZE = 200_000;
const MAX_SUMMARY = 420;

function stripFrontMatter(value: string): string {
  if (!value.startsWith("---")) return value;
  const end = value.indexOf("\n---", 3);
  return end === -1 ? value : value.slice(end + 4);
}

function cleanInline(value: string): string {
  return value
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/<[^>]+>/g, "")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/[*_~]{1,3}([^*_~]+)[*_~]{1,3}/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

function isSkippable(line: string): boolean {
  const value = line.trim();
  if (!value) return true;
  if (value.startsWith("#")) return true;
  if (value.startsWith("```") || value.startsWith("~~~")) return true;
  if (value.startsWith("[![") || value.startsWith("![")) return true;
  if (value.startsWith("<")) return true;
  if (/^[-*_]{3,}$/.test(value)) return true;
  if (/^>\s*$/.test(value)) return true;
  return false;
}

function limitSummary(value: string): string {
  if (value.length <= MAX_SUMMARY) return value;
  const clipped = value.slice(0, MAX_SUMMARY);
  const sentence = Math.max(
    clipped.lastIndexOf(". "),
    clipped.lastIndexOf("! "),
    clipped.lastIndexOf("? "),
  );
  if (sentence > MAX_SUMMARY * 0.5) return clipped.slice(0, sentence + 1).trim();
  const space = clipped.lastIndexOf(" ");
  return `${clipped.slice(0, space > 0 ? space : MAX_SUMMARY).trim()}…`;
}

/** Extracts the first prose paragraph, skipping badges, headings and HTML. */
export function summarizeReadme(value: string): string {
  const lines = stripFrontMatter(value)
    .replace(/\r\n?/g, "\n")
    .slice(0, MAX_READ_SIZE)
    .split("\n");

  let started = false;
  let paragraph: string[] = [];

  for (const line of lines) {
    if (isSkippable(line)) {
      if (started) break;
      continue;
    }

    const cleaned = cleanInline(line.replace(/^\s*>\s?/, ""));
    if (!cleaned) {
      if (started) break;
      continue;
    }

    started = true;
    paragraph.push(cleaned);
  }

  const summary = paragraph.join(" ").trim();
  return summary ? limitSummary(summary) : "";
}

export async function readProjectDescription(directory: string): Promise<string> {
  if (!directory) return "";
  for (const name of README_CANDIDATES) {
    try {
      const contents = await readFile(join(directory, name), "utf8");
      const summary = summarizeReadme(contents);
      if (summary) return summary;
    } catch {
      // Try the next spelling; a missing README is normal.
    }
  }
  return "";
}

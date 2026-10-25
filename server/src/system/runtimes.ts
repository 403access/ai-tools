import type { SystemRuntime } from "../types.ts";
import { findExecutable } from "./commands.ts";
import { TOOL_COMMANDS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { lines } from "./util.ts";

export async function collectRuntimes(run: CommandRunner): Promise<SystemRuntime[]> {
  const results = await Promise.all(
    TOOL_COMMANDS.map(async (tool): Promise<SystemRuntime | null> => {
      const path = findExecutable(tool.command);
      if (!path) return null;
      const result = await run(path, tool.args, 3_000);
      const output = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
      if (!result.ok && !output) return null;
      return {
        name: tool.name,
        version: cleanVersion(output),
        path,
        kind: tool.kind,
      };
    }),
  );
  return results.filter((entry): entry is SystemRuntime => entry !== null);
}

export function cleanVersion(value: string): string {
  const line = lines(value).find((entry) => !/^(usage|help|available commands)/i.test(entry)) ?? "";
  let version = line.replace(/\s+/g, " ").trim();
  const labelled = /^(?:Client Version|Server Version|clientVersion|serverVersion)\s*:\s*(.+)$/i.exec(version);
  if (labelled?.[1]) version = labelled[1].trim();
  if (/^v?\d/.test(version)) {
    const first = version.split(/\s+/)[0];
    if (first) version = first;
  }
  if (version.length > 120) version = `${version.slice(0, 117)}…`;
  return version || "installed";
}

import type { SystemBrewPackage, SystemHomebrew } from "../types.ts";
import { findExecutable } from "./commands.ts";
import { COMMAND_TIMEOUT_MS, LONG_COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { firstLine, lines, text } from "./util.ts";

export async function collectHomebrew(run: CommandRunner): Promise<SystemHomebrew> {
  const brew = findExecutable("brew") ?? findExecutable("brew", ["/opt/homebrew/bin", "/usr/local/bin", "/home/linuxbrew/.linuxbrew/bin"]);
  if (!brew) {
    return { available: false, formulaCount: 0, caskCount: 0, outdatedCount: 0, packages: [] };
  }

  const env = { ...process.env, HOMEBREW_NO_AUTO_UPDATE: "1", HOMEBREW_NO_INSTALL_CLEANUP: "1" };
  const [versionResult, prefixResult, formulaResult, caskResult, outdatedResult] = await Promise.all([
    run(brew, ["--version"], COMMAND_TIMEOUT_MS, env),
    run(brew, ["--prefix"], COMMAND_TIMEOUT_MS, env),
    run(brew, ["list", "--versions"], LONG_COMMAND_TIMEOUT_MS, env),
    run(brew, ["list", "--cask", "--versions"], LONG_COMMAND_TIMEOUT_MS, env),
    run(brew, ["outdated", "--quiet"], LONG_COMMAND_TIMEOUT_MS, env),
  ]);

  const outdated = new Set(lines(text(outdatedResult)));
  const formulae = parseBrewVersions(text(formulaResult), "formula", outdated);
  const casks = parseBrewVersions(text(caskResult), "cask", outdated);
  const packages = [...formulae, ...casks].sort((a, b) => {
    if (a.kind !== b.kind) return a.kind === "formula" ? -1 : 1;
    return a.name.localeCompare(b.name);
  });

  return {
    available: true,
    version: firstLine(text(versionResult))?.replace(/^Homebrew\s+/, "Homebrew "),
    prefix: firstLine(text(prefixResult)),
    formulaCount: formulae.length,
    caskCount: casks.length,
    outdatedCount: outdated.size,
    packages,
  };
}

export function parseBrewVersions(
  value: string,
  kind: "formula" | "cask",
  outdated: Set<string>,
): SystemBrewPackage[] {
  return lines(value).flatMap((line) => {
    const parts = line.split(/\s+/);
    const name = parts[0];
    if (!name) return [];
    return [{
      name,
      version: parts.slice(1).join(" ") || "unknown",
      kind,
      outdated: outdated.has(name),
    }];
  });
}

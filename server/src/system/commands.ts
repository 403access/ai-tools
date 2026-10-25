import { execFile } from "node:child_process";
import { accessSync, constants } from "node:fs";
import { delimiter, join } from "node:path";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";

export const defaultRunner: CommandRunner = (command, args, timeoutMs = COMMAND_TIMEOUT_MS, env) =>
  new Promise((resolve) => {
    execFile(
      command,
      args,
      {
        timeout: timeoutMs,
        maxBuffer: 16 * 1024 * 1024,
        encoding: "utf8",
        windowsHide: true,
        env: env ?? process.env,
      },
      (error, stdout, stderr) => {
        resolve({
          ok: !error,
          stdout: typeof stdout === "string" ? stdout : "",
          stderr: typeof stderr === "string" ? stderr : "",
        });
      },
    );
  });

export function findExecutable(name: string, extraDirectories: string[] = []): string | undefined {
  const extensions = process.platform === "win32"
    ? ["", ...(process.env.PATHEXT ?? ".EXE;.CMD;.BAT").split(";").filter(Boolean)]
    : [""];
  const directories = [
    ...(process.env.PATH ?? "").split(delimiter),
    ...extraDirectories,
  ].filter(Boolean);

  for (const directory of directories) {
    for (const extension of extensions) {
      const candidate = join(directory, `${name}${extension}`);
      try {
        accessSync(candidate, process.platform === "win32" ? constants.F_OK : constants.X_OK);
        return candidate;
      } catch {
        // Try the next candidate.
      }
    }
  }
  return undefined;
}

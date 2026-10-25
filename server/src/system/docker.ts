import type { SystemDocker } from "../types.ts";
import { findExecutable } from "./commands.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { firstLine, lines, parseJSONRecord, stringValue, text } from "./util.ts";

/** Keeps `docker ps` off the critical path for the five-second system poll. */
export class DockerCollector {
  private last: { at: number; value: SystemDocker | null } | null = null;

  async collect(run: CommandRunner): Promise<SystemDocker | null> {
    const now = Date.now();
    if (this.last && now - this.last.at < 10_000) return this.last.value;

    const path = findExecutable("docker");
    if (!path) {
      this.last = { at: now, value: null };
      return null;
    }

    const [versionResult, psResult] = await Promise.all([
      run(path, ["--version"], COMMAND_TIMEOUT_MS),
      run(path, ["ps", "--format", "{{json .}}"], COMMAND_TIMEOUT_MS),
    ]);
    const containers = lines(text(psResult)).flatMap((line) => {
      const entry = parseJSONRecord(line);
      if (!entry) return [];
      const id = stringValue(entry.ID);
      const name = stringValue(entry.Names);
      if (!id || !name) return [];
      return [{
        id,
        name,
        image: stringValue(entry.Image) ?? "",
        state: stringValue(entry.State) ?? "",
        status: stringValue(entry.Status) ?? "",
        ports: stringValue(entry.Ports),
        created: stringValue(entry.CreatedAt),
      }];
    });
    const value: SystemDocker = {
      available: psResult.ok,
      version: parseDockerVersion(text(versionResult)),
      running: containers.filter((container) => /^running$/i.test(container.state)).length,
      containers,
    };
    this.last = { at: now, value };
    return value;
  }
}

export function parseDockerVersion(value: string): string | undefined {
  return /Docker version\s+([^,\s]+)/i.exec(value)?.[1] ?? firstLine(value);
}

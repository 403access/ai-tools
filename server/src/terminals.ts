import type { HubDB } from "./db.ts";
import type { Hub } from "./hub.ts";
import { OpenCodeClient, OpenCodeError } from "./opencode.ts";
import type {
  Terminal,
  TerminalCreateInput,
  TerminalUpdateInput,
} from "./types.ts";

/** The terminal operations the HTTP layer needs; injectable for tests. */
export interface TerminalStore {
  list(force?: boolean): Promise<Terminal[]>;
  create(input: TerminalCreateInput): Promise<Terminal>;
  update(id: string, input: TerminalUpdateInput, location?: string): Promise<Terminal>;
  remove(id: string, location?: string): Promise<void>;
}

/**
 * PTYs owned by the OpenCode service. OpenCode scopes its terminal registry by
 * location (a working directory), so "all terminals" means querying the
 * default location plus every project the hub knows about and merging the
 * results. Terminal ids are stable across locations, which lets the merge
 * deduplicate a directory listed twice.
 */
export class TerminalService implements TerminalStore {
  private readonly hub: Hub;
  private readonly db: HubDB;

  private cache: { at: number; value: Terminal[] } | null = null;
  private inFlight: Promise<Terminal[]> | null = null;
  private locationByID = new Map<string, string>();

  constructor(hub: Hub, db: HubDB, private readonly cacheTTLMs = 1_500) {
    this.hub = hub;
    this.db = db;
  }

  async list(force = false): Promise<Terminal[]> {
    const now = Date.now();
    if (!force && this.cache && now - this.cache.at < this.cacheTTLMs) {
      return this.cache.value;
    }
    if (this.inFlight) return this.inFlight;

    this.inFlight = this.load()
      .then((value) => {
        this.cache = { at: Date.now(), value };
        return value;
      })
      .finally(() => {
        this.inFlight = null;
      });
    return this.inFlight;
  }

  async create(input: TerminalCreateInput): Promise<Terminal> {
    const client = await this.client();
    const location =
      input.location?.trim() || (await client.listPtys()).location.directory;
    const response = await client.createPty(
      {
        ...input,
        cwd: input.cwd?.trim() || location,
        location: undefined,
      },
      location,
    );
    const terminal = toTerminal(response.data, response.location?.directory ?? location);
    this.locationByID.set(terminal.id, terminal.location);
    this.invalidate();
    return terminal;
  }

  async update(id: string, input: TerminalUpdateInput, location?: string): Promise<Terminal> {
    const client = await this.client();
    const directory = await this.resolveLocation(id, location);
    const response = await client.updatePty(id, input, directory);
    const terminal = toTerminal(response.data, response.location?.directory ?? directory);
    this.locationByID.set(terminal.id, terminal.location);
    this.invalidate();
    return terminal;
  }

  async remove(id: string, location?: string): Promise<void> {
    const client = await this.client();
    const directory = await this.resolveLocation(id, location);
    await client.removePty(id, directory);
    this.locationByID.delete(id);
    this.invalidate();
  }

  /** Everything the hub needs to open the upstream terminal socket. */
  async socketTarget(
    id: string,
    location?: string,
    cursor?: string,
  ): Promise<{ url: string; authorization: string; location: string }> {
    const client = await this.client();
    const directory = await this.resolveLocation(id, location);
    return {
      url: client.ptySocketURL(id, { directory, cursor }),
      authorization: client.authorizationHeader,
      location: directory,
    };
  }

  private async load(): Promise<Terminal[]> {
    const client = await this.client();
    const first = await client.listPtys();
    const defaultLocation = first.location?.directory ?? "~";

    const directories = [defaultLocation];
    const seen = new Set(directories);
    for (const project of this.db.getProjects()) {
      for (const directory of [project.canonical, ...(project.sandboxes ?? [])]) {
        if (!directory || seen.has(directory)) continue;
        seen.add(directory);
        directories.push(directory);
      }
    }
    // Terminals created from the app (or an earlier list) can live outside a
    // known project, for example in a scratch directory. Keep querying those
    // locations so they do not disappear from the list.
    for (const location of this.locationByID.values()) {
      if (!location || seen.has(location)) continue;
      seen.add(location);
      directories.push(location);
    }

    const byID = new Map<string, Terminal>();
    for (const terminal of first.data ?? []) {
      byID.set(terminal.id, toTerminal(terminal, defaultLocation));
    }

    const others = directories.slice(1, 80);
    const results = await mapLimit(others, 6, async (directory) => {
      try {
        return { directory, ptys: (await client.listPtys(directory)).data ?? [] };
      } catch (caught) {
        // A stale project directory (or a location OpenCode has forgotten) is
        // expected; one bad location must not hide the terminals in the rest.
        if (caught instanceof OpenCodeError && caught.status === 404) {
          return { directory, ptys: [] };
        }
        this.hub.log(
          "debug",
          `terminals: could not list ${directory}: ${caught instanceof Error ? caught.message : String(caught)}`,
        );
        return { directory, ptys: [] };
      }
    });

    for (const result of results) {
      for (const pty of result.ptys) {
        if (byID.has(pty.id)) continue;
        byID.set(pty.id, toTerminal(pty, result.directory));
      }
    }

    this.locationByID = new Map(
      Array.from(byID.values()).map((terminal) => [terminal.id, terminal.location]),
    );

    return Array.from(byID.values()).sort(compareTerminals);
  }

  private async resolveLocation(id: string, provided?: string): Promise<string> {
    if (provided?.trim()) return provided.trim();
    const known = this.locationByID.get(id);
    if (known) return known;

    const terminals = await this.list(true);
    const found = terminals.find((terminal) => terminal.id === id);
    if (!found) throw new OpenCodeError("Terminal not found", 404);
    return found.location;
  }

  private async client(): Promise<OpenCodeClient> {
    const client = await this.hub.ensureClient();
    if (!client) throw new OpenCodeError("OpenCode is offline", 503);
    return client;
  }

  private invalidate(): void {
    this.cache = null;
  }
}

function toTerminal(
  pty: {
    id: string;
    title: string;
    command: string;
    args: string[];
    cwd: string;
    status: "running" | "exited";
    pid: number;
    exitCode?: number;
  },
  location: string,
): Terminal {
  return {
    id: pty.id,
    title: pty.title || pty.command || "Terminal",
    command: pty.command,
    args: pty.args ?? [],
    cwd: pty.cwd,
    status: pty.status,
    pid: pty.pid,
    ...(pty.exitCode === undefined ? {} : { exitCode: pty.exitCode }),
    location,
  };
}

function compareTerminals(left: Terminal, right: Terminal): number {
  if (left.status !== right.status) return left.status === "running" ? -1 : 1;
  const byTitle = left.title.localeCompare(right.title, undefined, { sensitivity: "base" });
  if (byTitle !== 0) return byTitle;
  return left.location.localeCompare(right.location);
}

/** Runs `fn` over `items` with at most `limit` promises in flight. */
async function mapLimit<T, R>(
  items: T[],
  limit: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;

  async function worker(): Promise<void> {
    for (;;) {
      const index = next++;
      if (index >= items.length) return;
      results[index] = await fn(items[index]!);
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, () => worker()),
  );
  return results;
}

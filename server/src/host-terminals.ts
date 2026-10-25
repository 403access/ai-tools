import { platform } from "node:os";
import type { HostTerminal, HostTerminalDetail } from "./types.ts";

/**
 * Terminal.app does not expose a way to attach to the master side of a PTY.
 * macOS automation can, however, read the visible text of a tab and run a
 * command in it, so that is the model here: a one-second text mirror plus a
 * command line. The shell runs in the terminal the user already has open.
 *
 * Only Terminal.app is supported for now. iTerm2 and the integrated terminals
 * in IDEs do not share this scripting model.
 */
export class HostTerminalError extends Error {
  readonly status: number;

  constructor(message: string, status = 503) {
    super(message);
    this.name = "HostTerminalError";
    this.status = status;
  }
}

export interface HostTerminalStore {
  list(force?: boolean): Promise<HostTerminal[]>;
  detail(tty: string, includeHistory?: boolean): Promise<HostTerminalDetail>;
  command(tty: string, command: string): Promise<void>;
  focus(tty: string): Promise<void>;
}

const TTY_PATTERN = /^ttys\d{1,6}$/;
const COMMAND_LIMIT = 16_384;

const LIST_SCRIPT = `
const Terminal = Application("Terminal");
if (!Terminal.running()) {
  JSON.stringify([]);
} else {
  const out = [];
  Terminal.windows().forEach((window, windowIndex) => {
    window.tabs().forEach((tab, tabIndex) => {
      out.push({
        window: windowIndex + 1,
        tab: tabIndex + 1,
        tty: tab.tty(),
        title: tab.customTitle() || "",
        busy: tab.busy(),
        processes: tab.processes(),
      });
    });
  });
  JSON.stringify(out);
}
`;

export class HostTerminalService implements HostTerminalStore {
  private cache: { at: number; value: HostTerminal[] } | null = null;
  private inFlight: Promise<HostTerminal[]> | null = null;
  private readonly cacheTTLMs: number;

  constructor(cacheTTLMs = 1_000) {
    this.cacheTTLMs = cacheTTLMs;
  }

  async list(force = false): Promise<HostTerminal[]> {
    if (platform() !== "darwin") return [];
    const now = Date.now();
    if (!force && this.cache && now - this.cache.at < this.cacheTTLMs) {
      return this.cache.value;
    }
    if (this.inFlight) return this.inFlight;

    this.inFlight = this.run(LIST_SCRIPT)
      .then((raw) => {
        const value = parseTerminals(raw);
        this.cache = { at: Date.now(), value };
        return value;
      })
      .finally(() => {
        this.inFlight = null;
      });
    return this.inFlight;
  }

  async detail(tty: string, includeHistory = false): Promise<HostTerminalDetail> {
    this.validateTTY(tty);
    const raw = await this.run(detailScript(tty, includeHistory));
    const found = parseDetail(raw);
    if (!found) throw new HostTerminalError("Terminal tab not found", 404);
    return found;
  }

  async command(tty: string, command: string): Promise<void> {
    this.validateTTY(tty);
    if (typeof command !== "string") {
      throw new HostTerminalError("command must be a string", 400);
    }
    if (command.length > COMMAND_LIMIT) {
      throw new HostTerminalError("command is too long", 413);
    }
    await this.run(commandScript(tty, command));
    this.cache = null;
  }

  async focus(tty: string): Promise<void> {
    this.validateTTY(tty);
    await this.run(focusScript(tty));
  }

  private validateTTY(tty: string): void {
    if (!TTY_PATTERN.test(tty)) {
      throw new HostTerminalError("Invalid terminal id", 400);
    }
  }

  private async run(script: string): Promise<string> {
    if (platform() !== "darwin") {
      throw new HostTerminalError("Terminal.app integration is only available on macOS", 501);
    }

    let process: ReturnType<typeof Bun.spawn>;
    try {
      process = Bun.spawn(["osascript", "-l", "JavaScript", "-e", script], {
        stdout: "pipe",
        stderr: "pipe",
        stdin: "ignore",
      });
    } catch (error) {
      throw new HostTerminalError(
        `Could not start macOS automation: ${error instanceof Error ? error.message : String(error)}`,
      );
    }

    const timer = setTimeout(() => {
      try {
        process.kill();
      } catch {
        // Already gone.
      }
    }, 8_000);

    try {
      const [stdout, stderr, code] = await Promise.all([
        new Response(process.stdout as ReadableStream).text(),
        new Response(process.stderr as ReadableStream).text(),
        process.exited,
      ]);
      if (code !== 0) {
        throw new HostTerminalError(automationMessage(stderr || stdout));
      }
      return stdout.trim();
    } finally {
      clearTimeout(timer);
    }
  }
}

function detailScript(tty: string, includeHistory: boolean): string {
  return `
const Terminal = Application("Terminal");
if (!Terminal.running()) {
  JSON.stringify(null);
} else {
  const target = ${JSON.stringify(`/dev/${tty}`)};
  const includeHistory = ${includeHistory ? "true" : "false"};
  let found = null;
  Terminal.windows().forEach((window, windowIndex) => {
    window.tabs().forEach((tab, tabIndex) => {
      if (tab.tty() === target) {
        found = {
          window: windowIndex + 1,
          tab: tabIndex + 1,
          tty: tab.tty(),
          title: tab.customTitle() || "",
          busy: tab.busy(),
          processes: tab.processes(),
          contents: tab.contents(),
        };
        if (includeHistory) found.history = tab.history();
      }
    });
  });
  JSON.stringify(found);
}
`;
}

function commandScript(tty: string, command: string): string {
  return `
const Terminal = Application("Terminal");
const target = ${JSON.stringify(`/dev/${tty}`)};
const command = ${JSON.stringify(command)};
let targetTab = null;
Terminal.windows().forEach((window) => {
  window.tabs().forEach((tab) => {
    if (tab.tty() === target) targetTab = tab;
  });
});
if (!targetTab) throw new Error("Terminal tab not found");
Terminal.doScript(command, { in: targetTab });
"ok";
`;
}

function focusScript(tty: string): string {
  return `
const Terminal = Application("Terminal");
const target = ${JSON.stringify(`/dev/${tty}`)};
let targetTab = null;
let targetWindow = null;
Terminal.windows().forEach((window) => {
  window.tabs().forEach((tab) => {
    if (tab.tty() === target) {
      targetTab = tab;
      targetWindow = window;
    }
  });
});
if (!targetTab || !targetWindow) throw new Error("Terminal tab not found");
Terminal.activate();
targetWindow.index = 1;
targetWindow.selectedTab = targetTab;
"ok";
`;
}

interface RawTerminal {
  window?: unknown;
  tab?: unknown;
  tty?: unknown;
  title?: unknown;
  busy?: unknown;
  processes?: unknown;
  contents?: unknown;
  history?: unknown;
}

function parseTerminals(raw: string): HostTerminal[] {
  if (!raw) return [];
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new HostTerminalError("Terminal.app returned an unreadable response");
  }
  if (!Array.isArray(value)) return [];

  const seen = new Set<string>();
  const terminals: HostTerminal[] = [];
  for (const entry of value) {
    const terminal = toTerminal(entry as RawTerminal);
    if (!terminal || seen.has(terminal.id)) continue;
    seen.add(terminal.id);
    terminals.push(terminal);
  }
  return terminals.sort((left, right) => left.window - right.window || left.tab - right.tab);
}

function parseDetail(raw: string): HostTerminalDetail | null {
  if (!raw || raw === "null") return null;
  let value: RawTerminal;
  try {
    value = JSON.parse(raw) as RawTerminal;
  } catch {
    throw new HostTerminalError("Terminal.app returned an unreadable response");
  }
  const terminal = toTerminal(value);
  if (!terminal) return null;
  return {
    ...terminal,
    contents: typeof value.contents === "string" ? value.contents : "",
    ...(typeof value.history === "string" ? { history: value.history } : {}),
  };
}

function toTerminal(raw: RawTerminal): HostTerminal | null {
  const ttyPath = typeof raw.tty === "string" ? raw.tty : "";
  const id = ttyPath.startsWith("/dev/") ? ttyPath.slice(5) : "";
  if (!TTY_PATTERN.test(id)) return null;
  const processes = Array.isArray(raw.processes)
    ? raw.processes.filter((entry): entry is string => typeof entry === "string")
    : [];
  return {
    id,
    tty: ttyPath,
    app: "Terminal",
    title: (typeof raw.title === "string" && raw.title.trim()) || processes.at(-1) || "Terminal",
    busy: raw.busy === true,
    processes,
    window: typeof raw.window === "number" ? raw.window : 0,
    tab: typeof raw.tab === "number" ? raw.tab : 0,
  };
}

function automationMessage(raw: string): string {
  const message = raw
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .at(-1) ?? "Terminal.app automation failed";

  if (/not allowed to send Apple events|not authorized|-1743/i.test(message)) {
    return "OpenCodeBar Hub is not allowed to control Terminal.app. Allow it in System Settings → Privacy & Security → Automation, then restart the hub.";
  }
  if (/not allowed to send keystrokes|assistive access|-1719/i.test(message)) {
    return "macOS blocked Terminal.app automation. Check Privacy & Security → Automation.";
  }
  return message.replace(/^execution error:\s*/i, "");
}

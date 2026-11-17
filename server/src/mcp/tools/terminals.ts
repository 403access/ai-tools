import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { readSocket, stripTerminalControl } from "../websocket.ts";
import type { ToolContext } from "./common.ts";
import { describeError, failure, jsonText, queryString, text } from "./common.ts";

const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;
const WRITE = { readOnlyHint: false, openWorldHint: false } as const;

function terminalPath(id: string): string {
  return `/api/terminals/${encodeURIComponent(id.trim())}`;
}

export function registerTerminalTools(server: McpServer, context: ToolContext): void {
  server.registerTool(
    "list_terminals",
    {
      title: "List terminals",
      description:
        "List every OpenCode PTY the hub knows about across projects, including terminals started in OpenCode's own TUI.",
      inputSchema: {
        refresh: z.boolean().optional().describe("Bypass the hub's short terminal-list cache."),
      },
      annotations: READ_ONLY,
    },
    async ({ refresh }) => {
      try {
        return jsonText(
          await context.client().get(`/api/terminals${queryString({ refresh: refresh ? 1 : undefined })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "start_terminal",
    {
      title: "Start a terminal",
      description:
        "Start an interactive shell (or a specific command) in a project directory on the hub host.",
      inputSchema: {
        location: z
          .string()
          .optional()
          .describe("OpenCode location for the PTY. Defaults to the hub's current directory."),
        cwd: z.string().optional().describe("Working directory. Defaults to the location."),
        title: z.string().optional().describe("Tab title."),
        command: z
          .string()
          .optional()
          .describe("Executable to run instead of the default shell."),
        args: z.array(z.string()).optional().describe("Arguments for `command`."),
        env: z
          .record(z.string(), z.string())
          .optional()
          .describe("Extra environment variables."),
      },
      annotations: WRITE,
    },
    async ({ location, cwd, title, command, args, env }) => {
      try {
        return jsonText(
          await context.client().post("/api/terminals", {
            ...(location ? { location } : {}),
            ...(cwd ? { cwd } : {}),
            ...(title ? { title } : {}),
            ...(command ? { command } : {}),
            ...(args?.length ? { args } : {}),
            ...(env ? { env } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_terminal",
    {
      title: "Get a terminal",
      description: "Read one terminal's id, title, location, size, process, and running state.",
      inputSchema: {
        terminal: z.string().describe("Terminal id, for example pty_..."),
      },
      annotations: READ_ONLY,
    },
    async ({ terminal }) => {
      try {
        return jsonText(await context.client().get(terminalPath(terminal)));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "update_terminal",
    {
      title: "Rename or resize a terminal",
      description:
        "Change a terminal's title or its PTY grid size. OpenCode applies resize over HTTP, not the socket.",
      inputSchema: {
        terminal: z.string().describe("Terminal id."),
        location: z.string().optional().describe("Location the terminal belongs to."),
        title: z.string().optional().describe("New tab title."),
        rows: z.number().int().min(1).max(5_000).optional().describe("Terminal rows."),
        cols: z.number().int().min(1).max(5_000).optional().describe("Terminal columns."),
      },
      annotations: WRITE,
    },
    async ({ terminal, location, title, rows, cols }) => {
      if (title === undefined && rows === undefined && cols === undefined) {
        return failure("Provide title, rows, or cols.");
      }
      if ((rows === undefined) !== (cols === undefined)) {
        return failure("Provide both rows and cols when resizing.");
      }
      try {
        return jsonText(
          await context.client().put(
            `${terminalPath(terminal)}${queryString({ location })}`,
            {
              ...(title !== undefined ? { title } : {}),
              ...(rows !== undefined && cols !== undefined ? { size: { rows, cols } } : {}),
            },
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "close_terminal",
    {
      title: "Close a terminal",
      description: "Stop the PTY process and remove the terminal.",
      inputSchema: {
        terminal: z.string().describe("Terminal id."),
        location: z.string().optional().describe("Location the terminal belongs to."),
      },
      annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: false },
    },
    async ({ terminal, location }) => {
      try {
        await context.client().delete(`${terminalPath(terminal)}${queryString({ location })}`);
        return text(`Closed terminal ${terminal.trim()}.`);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "read_terminal",
    {
      title: "Read terminal output",
      description:
        "Attach to a terminal for a short bounded window and return its recent output with colour escapes removed. " +
        "Pass a cursor from a previous read to continue after the replayed history.",
      inputSchema: {
        terminal: z.string().describe("Terminal id."),
        location: z.string().optional().describe("Location the terminal belongs to."),
        cursor: z
          .number()
          .int()
          .min(0)
          .optional()
          .describe("Absolute output position from an earlier read."),
        waitMs: z
          .number()
          .int()
          .min(100)
          .max(20_000)
          .optional()
          .describe("How long to listen. Defaults to 1,500 ms."),
        raw: z.boolean().optional().describe("Keep colour and cursor escapes."),
      },
      annotations: READ_ONLY,
    },
    async ({ terminal, location, cursor, waitMs, raw }) => {
      try {
        const result = await readSocket(
          context.client(),
          `${terminalPath(terminal)}/socket`,
          { location, cursor },
          { waitMs, raw },
        );
        return jsonText({ terminal: terminal.trim(), ...result });
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "send_terminal_input",
    {
      title: "Type into a terminal",
      description:
        "Send text to a running terminal, optionally pressing Enter, and return the output produced during the wait. " +
        "The shell keeps running after the tool returns.",
      inputSchema: {
        terminal: z.string().describe("Terminal id."),
        input: z.string().describe("Text to type, for example `git status` or a control sequence."),
        location: z.string().optional().describe("Location the terminal belongs to."),
        enter: z
          .boolean()
          .optional()
          .describe("Append a carriage return. Defaults to true unless the input already ends with one."),
        waitMs: z
          .number()
          .int()
          .min(100)
          .max(20_000)
          .optional()
          .describe("How long to collect output. Defaults to 2,000 ms."),
        raw: z.boolean().optional().describe("Keep colour and cursor escapes."),
      },
      annotations: WRITE,
    },
    async ({ terminal, input, location, enter, waitMs, raw }) => {
      const pressEnter = enter ?? (!input.endsWith("\r") && !input.endsWith("\n"));
      const payload = pressEnter ? `${input}\r` : input;
      try {
        const result = await readSocket(
          context.client(),
          `${terminalPath(terminal)}/socket`,
          { location },
          { input: payload, waitMs: waitMs ?? 2_000, raw },
        );
        return jsonText({
          terminal: terminal.trim(),
          sent: stripTerminalControl(payload),
          ...result,
        });
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_host_terminals",
    {
      title: "List Terminal.app tabs",
      description:
        "List the tabs already open in Terminal.app on the hub host, including their tty and current text.",
      inputSchema: {
        refresh: z.boolean().optional().describe("Bypass the short tab-list cache."),
      },
      annotations: READ_ONLY,
    },
    async ({ refresh }) => {
      try {
        return jsonText(
          await context.client().get(
            `/api/host-terminals${queryString({ refresh: refresh ? 1 : undefined })}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_host_terminal",
    {
      title: "Read a Terminal.app tab",
      description:
        "Read the live text mirror of one Terminal.app tab. Pass history to include scrollback.",
      inputSchema: {
        tty: z.string().describe("TTY device name, for example ttys003."),
        history: z.boolean().optional().describe("Include the tab's scrollback history."),
      },
      annotations: READ_ONLY,
    },
    async ({ tty, history }) => {
      try {
        return jsonText(
          await context.client().get(
            `/api/host-terminals/${encodeURIComponent(tty.trim())}${queryString({
              history: history ? 1 : undefined,
            })}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "run_host_terminal_command",
    {
      title: "Run a line in Terminal.app",
      description:
        "Type one line and press Enter in an existing Terminal.app tab on the hub host.",
      inputSchema: {
        tty: z.string().describe("TTY device name, for example ttys003."),
        command: z.string().describe("Command line to run."),
      },
      annotations: WRITE,
    },
    async ({ tty, command }) => {
      try {
        await context.client().post(
          `/api/host-terminals/${encodeURIComponent(tty.trim())}/command`,
          { command },
        );
        return text(`Sent the command to ${tty.trim()}.`);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "focus_host_terminal",
    {
      title: "Focus a Terminal.app tab",
      description: "Bring an existing Terminal.app tab to the front on the hub host.",
      inputSchema: {
        tty: z.string().describe("TTY device name, for example ttys003."),
      },
      annotations: WRITE,
    },
    async ({ tty }) => {
      try {
        await context.client().post(
          `/api/host-terminals/${encodeURIComponent(tty.trim())}/focus`,
        );
        return text(`Focused ${tty.trim()}.`);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );
}
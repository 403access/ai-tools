import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  describeError,
  failure,
  findProject,
  jsonText,
  queryString,
  text,
  type ToolContext,
} from "./common.ts";

const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;
const WRITE = { readOnlyHint: false, openWorldHint: false } as const;

/** Endpoints that need a stream/binary client instead of one JSON request. */
const GENERIC_BLOCKED = [
  /^\/api\/event$/,
  /^\/api\/docs$/,
  /^\/api\/openapi\.json$/,
  /\/socket$/,
  /^\/api\/files\/raw$/,
  /\/icon$/,
  /^\/api\/deployments\/ota\/[a-z0-9][a-z0-9-]{5,63}(?:\/|$)/,
];

export function registerHubTools(server: McpServer, context: ToolContext): void {
  server.registerTool(
    "get_hub_health",
    {
      title: "Get hub and OpenCode health",
      description:
        "Read the hub's version, uptime, cache counts, device count, and whether the local OpenCode service is reachable.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/health"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_hub_info",
    {
      title: "Get hub server info",
      description:
        "Read the hub's version, process id, reachable URLs, capabilities, and health in one call.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/info"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_devices",
    {
      title: "List connected devices",
      description:
        "List the Mac, iPhone, and iPad clients that have connected to this hub recently.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/devices"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_usage",
    {
      title: "Get usage and plan limits",
      description:
        "Read the hub's cached Go plan usage windows together with the OpenCode usage totals it stores for the Usage tab.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/usage"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_stats",
    {
      title: "Get global or per-project stats",
      description:
        "Read OpenCode's aggregate statistics: steps, prompts, sessions, cost, tokens, models, and tool reliability. " +
        "Pass a project to scope the numbers to that checkout.",
      inputSchema: {
        project: z
          .string()
          .optional()
          .describe("Optional project display name, folder name, id, or absolute checkout path."),
      },
      annotations: READ_ONLY,
    },
    async ({ project }) => {
      try {
        const client = context.client();
        let projectID: string | undefined;
        if (project?.trim()) {
          const resolved = await findProject(client, project);
          if ("error" in resolved) return failure(resolved.error);
          projectID = resolved.project.id;
        }
        return jsonText(
          await client.get(
            `/api/experimental/session/stats${queryString({ project: projectID })}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_sync_snapshot",
    {
      title: "Read the incremental sync feed",
      description:
        "Read the hub's session/project change feed. Omit `since` for a full snapshot; pass a revision to get only rows and tombstones after it.",
      inputSchema: {
        since: z
          .number()
          .int()
          .min(0)
          .optional()
          .describe("Revision returned by an earlier sync call."),
      },
      annotations: READ_ONLY,
    },
    async ({ since }) => {
      try {
        return jsonText(
          await context.client().get(`/api/sync${queryString({ since })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "sync_hub",
    {
      title: "Force a hub sync",
      description:
        "Ask the hub to poll OpenCode now instead of waiting for the next scheduled refresh.",
      inputSchema: {},
      annotations: WRITE,
    },
    async () => {
      try {
        return jsonText(await context.client().post("/api/sync"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_settings",
    {
      title: "Get hub settings",
      description:
        "Read the event throttle, prevent-sleep flag, and concurrent-agent limit together with their allowed ranges.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/settings"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "update_settings",
    {
      title: "Update hub settings",
      description:
        "Change the event throttle (milliseconds), prevent-sleep, or concurrent-agent limit. Values are clamped by the hub.",
      inputSchema: {
        eventThrottleMs: z
          .number()
          .int()
          .optional()
          .describe("How long the hub folds live events before delivery, in milliseconds."),
        preventSleep: z
          .boolean()
          .optional()
          .describe("Keep the Mac awake while sessions are running."),
        maxConcurrentAgents: z
          .number()
          .int()
          .optional()
          .describe("Maximum top-level sessions the hub starts at once. 0 disables the limit."),
      },
      annotations: WRITE,
    },
    async ({ eventThrottleMs, preventSleep, maxConcurrentAgents }) => {
      if (
        eventThrottleMs === undefined &&
        preventSleep === undefined &&
        maxConcurrentAgents === undefined
      ) {
        return failure("Provide eventThrottleMs, preventSleep, or maxConcurrentAgents.");
      }
      try {
        return jsonText(
          await context.client().patch("/api/settings", {
            ...(eventThrottleMs !== undefined ? { eventThrottleMs } : {}),
            ...(preventSleep !== undefined ? { preventSleep } : {}),
            ...(maxConcurrentAgents !== undefined ? { maxConcurrentAgents } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "restart_hub",
    {
      title: "Restart the hub",
      description:
        "Ask the hub process to restart. The request returns before the new process starts, so reconnect after a moment.",
      inputSchema: {},
      annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: false },
    },
    async () => {
      try {
        return jsonText(await context.client().post("/api/server/restart"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "search_sessions",
    {
      title: "Search sessions",
      description:
        "Search cached session titles and directories. This is the hub's own full-text-ish search and works when OpenCode is offline.",
      inputSchema: {
        query: z.string().describe("Text to find in session titles or directories."),
        limit: z
          .number()
          .int()
          .min(1)
          .max(500)
          .optional()
          .describe("Maximum sessions to return. Defaults to 50."),
      },
      annotations: READ_ONLY,
    },
    async ({ query, limit }) => {
      try {
        return jsonText(
          await context.client().get(
            `/api/search${queryString({ q: query, limit })}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "hub_request",
    {
      title: "Call any Hub API endpoint",
      description:
        "Escape hatch for a hub endpoint that does not have a dedicated tool. Send one authenticated JSON request; " +
        "the path must start with /api/. Streaming and binary routes (SSE, WebSockets, raw files, icons, OTA downloads) are refused — use the dedicated tools for those.",
      inputSchema: {
        method: z
          .enum(["GET", "POST", "PUT", "PATCH", "DELETE"])
          .optional()
          .describe("HTTP method. Defaults to GET."),
        path: z
          .string()
          .describe("Hub API path, for example /api/session or /api/project/prj_1/changes."),
        query: z
          .record(z.string(), z.union([z.string(), z.number(), z.boolean()]))
          .optional()
          .describe("Query parameters. Booleans become true/false strings."),
        body: z
          .record(z.string(), z.unknown())
          .optional()
          .describe("JSON body for POST, PUT, or PATCH."),
      },
      annotations: { readOnlyHint: false, openWorldHint: false },
    },
    async ({ method, path, query, body }) => {
      const requestMethod = method ?? "GET";
      const clean = path.trim();
      if (!clean.startsWith("/api/")) {
        return failure("The path must start with /api/.");
      }
      if (clean.includes("..") || clean.includes("://")) {
        return failure("The path must be a hub API path, not a URL.");
      }
      if (GENERIC_BLOCKED.some((pattern) => pattern.test(clean))) {
        return failure(
          "That route streams data or returns a binary file. Use the dedicated tool for it instead.",
        );
      }
      if (requestMethod !== "GET" && requestMethod !== "DELETE" && !body) {
        return failure(`${requestMethod} needs a JSON body.`);
      }

      const params = new URLSearchParams();
      for (const [key, value] of Object.entries(query ?? {})) {
        params.set(key, String(value));
      }
      const suffix = params.size
        ? `${clean.includes("?") ? "&" : "?"}${params.toString()}`
        : "";
      try {
        const result = await context.client().request<unknown>(`${clean}${suffix}`, {
          method: requestMethod,
          ...(body ? { body: JSON.stringify(body) } : {}),
        });
        return result === null
          ? text("The hub returned an empty response.")
          : jsonText(result);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );
}
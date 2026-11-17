import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { ToolContext } from "./common.ts";
import { describeError, failure, jsonText, queryString } from "./common.ts";

const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;
const WRITE = { readOnlyHint: false, openWorldHint: false } as const;

const MEDIA_ACTIONS = [
  "play",
  "pause",
  "toggle",
  "stop",
  "next",
  "previous",
  "back15",
  "forward15",
  "volume",
  "mute",
] as const;

export function registerSystemTools(server: McpServer, context: ToolContext): void {
  server.registerTool(
    "get_system_info",
    {
      title: "Get the host system snapshot",
      description:
        "Read CPU, memory, storage, battery, network, displays, audio, thermal state, processes, runtimes, Homebrew, Docker, security, and installed apps for the Mac running the hub.",
      inputSchema: {
        refresh: z.boolean().optional().describe("Bypass the hub's cached system snapshot."),
      },
      annotations: READ_ONLY,
    },
    async ({ refresh }) => {
      try {
        return jsonText(
          await context.client().get(`/api/system${queryString({ refresh: refresh ? 1 : undefined })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_app_detail",
    {
      title: "Get installed app details",
      description:
        "Read bundle facts and app-specific inventory (for example Xcode simulators) for one installed app.",
      inputSchema: {
        path: z.string().describe("Absolute path to the .app bundle."),
      },
      annotations: READ_ONLY,
    },
    async ({ path }) => {
      try {
        return jsonText(
          await context.client().get(`/api/system/apps/detail${queryString({ path })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "manage_app",
    {
      title: "Manage an installed app",
      description:
        "Run a supported app action, such as deleting an Xcode simulator or cache. Use get_app_detail to see available actions.",
      inputSchema: {
        path: z.string().describe("Absolute path to the .app bundle."),
        action: z.string().describe("Action id from get_app_detail."),
        target: z.string().optional().describe("Optional action target, such as a simulator id."),
      },
      annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: false },
    },
    async ({ path, action, target }) => {
      try {
        return jsonText(
          await context.client().post("/api/system/apps/action", {
            path,
            action,
            ...(target ? { target } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "control_media",
    {
      title: "Control media playback",
      description:
        "Play, pause, skip, or change the volume of the host's current media player.",
      inputSchema: {
        action: z.enum(MEDIA_ACTIONS).describe("Media command."),
        value: z
          .number()
          .min(0)
          .max(100)
          .optional()
          .describe("Volume percentage for the volume action."),
      },
      annotations: WRITE,
    },
    async ({ action, value }) => {
      try {
        return jsonText(
          await context.client().post("/api/media", {
            action,
            ...(value !== undefined ? { value } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_remote_status",
    {
      title: "Get remote desktop status",
      description:
        "Read the screen-capture helper's state, display geometry, frame rate, quality, and macOS permission state.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/remote"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "configure_remote",
    {
      title: "Configure remote desktop",
      description:
        "Change the remote desktop frame rate, JPEG quality, maximum width, or selected display.",
      inputSchema: {
        fps: z.number().int().positive().optional().describe("Frames per second."),
        quality: z.number().min(0).max(1).optional().describe("JPEG quality from 0 to 1."),
        maxWidth: z.number().int().positive().optional().describe("Maximum captured width."),
        displayID: z.number().int().nonnegative().optional().describe("Display id to capture."),
      },
      annotations: WRITE,
    },
    async ({ fps, quality, maxWidth, displayID }) => {
      if (
        fps === undefined &&
        quality === undefined &&
        maxWidth === undefined &&
        displayID === undefined
      ) {
        return failure("Provide fps, quality, maxWidth, or displayID.");
      }
      try {
        return jsonText(
          await context.client().post("/api/remote/configure", {
            ...(fps !== undefined ? { fps } : {}),
            ...(quality !== undefined ? { quality } : {}),
            ...(maxWidth !== undefined ? { maxWidth } : {}),
            ...(displayID !== undefined ? { displayID } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "request_remote_permissions",
    {
      title: "Request remote desktop permissions",
      description:
        "Ask macOS on the hub host to prompt for Screen Recording and/or Accessibility permission. The prompt appears on the Mac.",
      inputSchema: {
        screenRecording: z.boolean().optional().describe("Request Screen Recording access."),
        accessibility: z.boolean().optional().describe("Request Accessibility access."),
      },
      annotations: WRITE,
    },
    async ({ screenRecording, accessibility }) => {
      if (screenRecording === undefined && accessibility === undefined) {
        return failure("Provide screenRecording, accessibility, or both.");
      }
      try {
        return jsonText(
          await context.client().post("/api/remote/permissions", {
            screenRecording: screenRecording === true,
            accessibility: accessibility === true,
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );
}
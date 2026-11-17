import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { ToolContext } from "./common.ts";
import { describeError, failure, jsonText, queryString } from "./common.ts";

const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;

export function registerDeploymentTools(server: McpServer, context: ToolContext): void {
  server.registerTool(
    "list_deployments",
    {
      title: "List app deployments",
      description:
        "List the OpenCodeBar builds installed on paired iPhones and iPads, newest first, with device and variant details.",
      inputSchema: {
        limit: z
          .number()
          .int()
          .min(1)
          .max(2_000)
          .optional()
          .describe("Maximum deployment rows. Defaults to 200."),
      },
      annotations: READ_ONLY,
    },
    async ({ limit }) => {
      try {
        return jsonText(
          await context.client().get(`/api/deployments${queryString({ limit: limit ?? 200 })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "scan_deployments",
    {
      title: "Scan connected devices",
      description:
        "Ask the hub to scan connected iPhones and iPads for installed OpenCodeBar builds. Returns device inventory and any scan errors.",
      inputSchema: {},
      annotations: { readOnlyHint: false, openWorldHint: true },
    },
    async () => {
      try {
        return jsonText(await context.client().post("/api/deployments/scan"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_ota_builds",
    {
      title: "List OTA builds",
      description:
        "Read published over-the-air iOS builds together with the latest build's install metadata and the current build job.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/deployments/ota"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_ota_build_status",
    {
      title: "Get OTA build progress",
      description: "Read the current or last over-the-air build job, including its phase and log tail.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/deployments/ota/build"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "start_ota_build",
    {
      title: "Build and publish an OTA install",
      description:
        "Start the hub's xcodebuild archive/export pipeline and publish the signed IPA for over-the-air installation on paired devices.",
      inputSchema: {},
      annotations: { readOnlyHint: false, openWorldHint: true },
    },
    async () => {
      try {
        return jsonText(await context.client().post("/api/deployments/ota/build"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );
}
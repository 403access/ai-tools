import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { ToolContext } from "./common.ts";
import { describeError, failure, jsonText, queryString } from "./common.ts";

const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;

export function registerFileTools(server: McpServer, context: ToolContext): void {
  server.registerTool(
    "list_directory",
    {
      title: "Browse host files",
      description:
        "List one folder on the hub host. Omit `path` for the browser roots. This is a read-only file browser shared with the Host tab.",
      inputSchema: {
        path: z.string().optional().describe("Absolute folder path. Omit to list roots."),
      },
      annotations: READ_ONLY,
    },
    async ({ path }) => {
      try {
        return jsonText(await context.client().get(`/api/files${queryString({ path })}`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "read_file",
    {
      title: "Read a host file",
      description:
        "Read a text file's metadata and contents from the hub host. Large files are truncated by the hub.",
      inputSchema: {
        path: z.string().describe("Absolute file path."),
      },
      annotations: READ_ONLY,
    },
    async ({ path }) => {
      try {
        return jsonText(
          await context.client().get(`/api/files/content${queryString({ path })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );
}
#!/usr/bin/env bun
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { discoverHub, HubClient } from "./hub.ts";
import { registerDeploymentTools } from "./tools/deployments.ts";
import { registerFileTools } from "./tools/files.ts";
import { registerHubTools } from "./tools/hub.ts";
import { registerProjectTools } from "./tools/projects.ts";
import { registerSessionTools } from "./tools/sessions.ts";
import { registerSystemTools } from "./tools/system.ts";
import { registerTerminalTools } from "./tools/terminals.ts";
import { registerVMTools } from "./tools/vms.ts";

const INSTRUCTIONS = `OpenCodeBar hub tools for the OpenCode projects, sessions, terminals, host, and virtual machines on this Mac.

Start with list_projects or list_sessions when a project or session id is uncertain. The same project can be
named by display name, folder name, id, or path; the tools resolve all four and ask you to disambiguate when
two checkouts share a name. create_session starts real work in a project checkout and sends the prompt, so it
appears immediately on the OpenCodeBar task board.

Sessions can be read (messages, changes, git, stats, children, forks, pending prompts, forms) and controlled
(prompt, queue, pause, stop, continue, fork, model, agent). Tasks are the top-level sessions on the board; use
list_tasks and update_task to resolve them. Projects expose their file tree, git graph, GitHub Actions flows,
scripts, documentation, and worktrees.

The host tools cover the system snapshot, files, media, remote-desktop configuration, OpenCode terminals, and
tabs open in Terminal.app. read_terminal and send_terminal_input attach briefly to a PTY over the hub's
WebSocket proxy; the shell keeps running after the tool returns. Virtual-machine tools cover the full NixOS
lifecycle, logs, serial console, and host setup steps. Deployment tools cover app installs and OTA builds.

Use hub_request only when no dedicated tool fits. It sends one authenticated JSON request to a /api/ path and
refuses streaming and binary routes. Treat restart_hub, remove_vm, close_terminal, stop_session, and the
destructive app actions as explicit user requests rather than automatic cleanup.`;

function client(): HubClient {
  return new HubClient(discoverHub());
}

export function createServer(getClient: () => HubClient = client): McpServer {
  const server = new McpServer(
    { name: "opencodebar", version: "2.0.0" },
    { instructions: INSTRUCTIONS },
  );

  const context = { client: getClient };
  registerHubTools(server, context);
  registerProjectTools(server, context);
  registerSessionTools(server, context);
  registerFileTools(server, context);
  registerTerminalTools(server, context);
  registerSystemTools(server, context);
  registerVMTools(server, context);
  registerDeploymentTools(server, context);

  return server;
}

if (import.meta.main) {
  const server = createServer();
  await server.connect(new StdioServerTransport());
  console.error("OpenCodeBar MCP server connected over stdio");
}
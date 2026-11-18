---
title: Agent tools (MCP)
sidebar_position: 4
---

# Agent tools (MCP)

OpenCodeBar ships a local [Model Context Protocol](https://modelcontextprotocol.io)
server that exposes the hub's full feature set to an agent. It is a stdio
server, so OpenCode, Claude Desktop, or any other MCP client starts it on the
same Mac as the hub and talks to the hub's authenticated HTTP API.

The server registers **95 tools**. They cover projects, sessions, tasks,
terminals, host files and system status, remote-desktop configuration, NixOS
virtual machines, deployments, settings, usage, and sync. An agent can start
work in a project, follow a running conversation, read its file patches and
stats, resolve a task, type into a terminal, inspect a guest's serial console,
and build an OTA install without a separate client.

## Start it

Start the hub first:

```sh
make hub
```

The repository's `opencode.json` already registers the server for OpenCode
sessions opened in this checkout:

```json
{
  "mcp": {
    "servers": {
      "opencodebar": {
        "type": "local",
        "command": ["bun", "server/src/mcp/server.ts"],
        "cwd": "."
      }
    }
  }
}
```

The Mac app's **Settings → MCP servers** card lists the servers found in the
global config and the repository checkout. It flags the OpenCodeBar server when
it is registered, copies the global registration command, opens the config in
Finder, and links back to this guide. The card is read-only: edit the config or
use `opencode mcp add`, then refresh the card or restart OpenCode.

Run it by hand to check the connection:

```sh
make mcp
# or: cd server && bun run mcp
```

Register it globally so every OpenCode session can use it, not only this
repository:

```sh
opencode mcp add opencodebar --global -- bun "$PWD/server/src/mcp/server.ts"
```

With OpenCode's default Code Mode the tools are grouped under
`tools.opencodebar`, for example `tools.opencodebar.list_projects`.

## Credentials

The server discovers the hub exactly like the apps. Precedence:

1. `$OPENCODEBAR_HUB_URL` / `$OPENCODEBAR_HUB_TOKEN`
2. `hubURL` / `hubToken` in `~/.config/opencode/opencodebar.json`
3. The generated `~/.config/opencode/opencodebar-hub.json`

The hub writes the third file on startup, so a local `make hub` needs no MCP
configuration. The token never appears in tool arguments or output; it is added
to each hub request by the server. For remote hubs, set both environment
variables in the MCP client's server definition.

## Tool groups

### Hub

`get_hub_health`, `get_hub_info`, `list_devices`, `get_usage`, `get_stats`,
`get_sync_snapshot`, `sync_hub`, `get_settings`, `update_settings`,
`restart_hub`, `search_sessions`, and `hub_request`.

`get_stats` accepts a project name or path and scopes the numbers to that
checkout. `get_sync_snapshot` reads the incremental session/project feed, and
`sync_hub` forces a poll. `hub_request` is an escape hatch for any JSON `/api/`
route that does not have a dedicated tool yet.

### Projects

`list_projects`, `get_project`, `get_project_changes`, `list_project_files`,
`get_project_git`, `get_project_flows`, `list_project_scripts`,
`run_project_script`, `get_project_documentation`,
`update_project_documentation`, `list_github_repositories`, `clone_repository`,
and `create_worktree`.

Project arguments accept a display name, folder name, project id, or absolute
checkout path. A name shared by two checkouts returns both candidates and asks
the caller to retry with the absolute path.

### Sessions and tasks

`create_session`, `list_sessions`, `get_session`, `list_session_messages`,
`send_prompt`, `queue_prompt`, `cancel_queued_prompt`, `start_queued_prompt`,
`pause_session`, `stop_session`, `continue_session`, `fork_session`,
`set_session_model`, `set_session_agent`, `list_child_sessions`,
`list_session_forks`, `get_session_changes`, `get_session_git`,
`get_session_stats`, `list_pending_prompts`, `cancel_pending_prompt`,
`list_session_forms`, `reply_session_form`, `cancel_session_form`,
`list_models`, `get_default_model`, `list_agents`, `list_tasks`, and
`update_task`.

`create_session` can choose the model and agent before sending the first
prompt. `send_prompt` accepts `delivery: "queue" | "steer"`, an ISO or
epoch-millisecond `startAt`, a `forMs` delay, and file attachments. `get_stats`,
`get_usage`, and the task board read cached data, so they still work when
OpenCode is offline.

### Terminals

`list_terminals`, `start_terminal`, `get_terminal`, `update_terminal`,
`close_terminal`, `read_terminal`, `send_terminal_input`,
`list_host_terminals`, `get_host_terminal`, `run_host_terminal_command`, and
`focus_host_terminal`.

`read_terminal` and `send_terminal_input` attach to the hub's WebSocket proxy for
a bounded window (1.5–2 seconds by default) and return the output with colour
escapes removed. The PTY keeps running after the tool returns. Use
`run_host_terminal_command` for a tab that is already open in Terminal.app.

### Host

`list_directory`, `read_file`, `get_system_info`, `get_app_detail`,
`manage_app`, `control_media`, `get_remote_status`, `configure_remote`, and
`request_remote_permissions`.

The file tools are read-only and share the Host tab's path restrictions. The
remote-desktop tools cover status, capture settings, and the macOS permission
prompts; the live frame/input stream stays in the iOS app because it is a
binary media flow rather than an agent action.

### Virtual machines

`list_vms`, `get_vm`, `create_vm`, `update_vm`, `remove_vm`, `control_vm`,
`get_vm_capabilities`, `get_vm_catalog`, `preview_vm`, `get_vm_log`,
`read_vm_console`, `get_vm_setup_status`, `start_vm_setup`, `cancel_vm_setup`,
`list_vm_setup_logs`, and `get_vm_setup_log`.

`control_vm` covers start, stop, restart, pause, resume, rebuild, and apply.
`preview_vm` renders configuration.nix and the flake before a VM exists, or
against an existing VM. `read_vm_console` can read or type into a running
guest's serial console.

### Deployments

`list_deployments`, `scan_deployments`, `get_ota_builds`,
`get_ota_build_status`, and `start_ota_build`.

These mirror the Settings → Deployments screen. Starting an OTA build runs
`xcodebuild` on the Mac and publishes the signed IPA through the hub.

## Examples

Start a task with a specific model:

> Create a session in project ai-tools using anthropic/claude-sonnet-4 that
> fixes the flaky MCP test, then send the prompt.

Follow the work and report back:

> Read the newest session in ai-tools, summarize its last five messages, and
> show the files it changed.

Resolve the board:

> List the tasks in review for the marketing website and mark the finished ones
> done.

Use the host:

> Start a terminal in the ai-tools checkout, run `make hub-test`, and show me
> the last 40 lines.

Manage a VM:

> Start the NixOS VM named builder, wait for it to boot, then read its serial
> console for the login prompt.

## Safety

The MCP server is a local automation surface, not a remote-access feature. It
holds the hub token, so anything the token can do is reachable by the agent:
prompting sessions, starting terminals, changing settings, and removing VMs.
Read-only tools carry MCP `readOnlyHint` annotations; destructive tools such as
`restart_hub`, `remove_vm`, `close_terminal`, `stop_session`, and
`manage_app` are marked separately.

- Run the hub locally with `make hub`; do not expose its port to an untrusted
  network.
- Register the server globally only on a Mac you control.
- Review destructive tool calls before approving them in your MCP client.
- The `hub_request` tool refuses SSE, WebSocket, icon, raw-file, and OTA-download
  routes. Use `read_terminal`, `send_terminal_input`, or `read_vm_console` for
  streams.
- The remote-desktop frame stream and signed OTA downloads are intentionally
  not agent tools.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `No OpenCodeBar hub token found` | Start the hub with `make hub`, or set `OPENCODEBAR_HUB_URL` and `OPENCODEBAR_HUB_TOKEN`. |
| `Could not reach the OpenCodeBar hub` | Check the hub is running and the URL is the one printed at startup, including the port. |
| A project name matches two checkouts | Retry with the absolute path shown by `list_projects`. |
| `OpenCode is offline` | The hub is up but the local OpenCode service is not. Reads still use the cache; writes need OpenCode. |
| Tools are missing in OpenCode | Restart the client after editing `opencode.json`, or use `opencode mcp add … --global`. |

The implementation lives in
[`server/src/mcp/`](https://github.com/403access/ai-tools/tree/main/server/src/mcp):
`server.ts` registers the tools, `hub.ts` discovers the hub and makes
authenticated requests, `tools/` has one module per feature area, and
`websocket.ts` handles the bounded terminal and console streams.
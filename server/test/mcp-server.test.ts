import { describe, expect, test } from "bun:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer } from "../src/mcp/server.ts";
import { HubClient } from "../src/mcp/hub.ts";

interface Recorded {
  url: string;
  method: string;
  body: unknown;
}

function fakeHub(handler?: (call: Recorded) => unknown) {
  const calls: Recorded[] = [];
  const fetchImpl = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const raw = typeof init?.body === "string" ? init.body : undefined;
    const body = raw ? JSON.parse(raw) : undefined;
    const call = { url, method, body };
    calls.push(call);
    const payload = handler?.(call) ?? { data: [] };
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;
  return { hub: new HubClient({ url: "http://127.0.0.1:8787", token: "secret" }, fetchImpl), calls };
}

async function pair(handler?: (call: Recorded) => unknown) {
  const { hub, calls } = fakeHub(handler);
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  const server = createServer(() => hub);
  await server.connect(serverTransport);
  const client = new Client({ name: "opencodebar-test", version: "1.0.0" });
  await client.connect(clientTransport);
  return { client, calls };
}

describe("OpenCodeBar MCP server", () => {
  test("registers tools for every hub feature area", async () => {
    const { client } = await pair();
    const { tools } = await client.listTools();
    const names = new Set(tools.map((tool) => tool.name));

    for (const name of [
      "get_hub_health",
      "hub_request",
      "list_projects",
      "create_session",
      "list_sessions",
      "send_prompt",
      "list_tasks",
      "list_session_messages",
      "get_session_changes",
      "list_terminals",
      "read_terminal",
      "send_terminal_input",
      "list_directory",
      "read_file",
      "get_system_info",
      "control_media",
      "get_remote_status",
      "list_vms",
      "control_vm",
      "read_vm_console",
      "list_deployments",
      "start_ota_build",
    ]) {
      expect(names.has(name), name).toBe(true);
    }
    expect(tools.length).toBeGreaterThanOrEqual(60);
    expect(new Set(tools.map((tool) => tool.name)).size).toBe(tools.length);
  });

  test("resolves a project and creates a session with a model", async () => {
    const { client, calls } = await pair((call) => {
      if (call.url.endsWith("/api/project")) {
        return [
          {
            id: "prj_1",
            canonical: "/tmp/demo",
            name: "Demo",
            vcs: "git",
            sandboxes: [],
            time: { created: 1, updated: 2 },
          },
        ];
      }
      if (call.url.endsWith("/api/session")) {
        return { data: { id: "ses_1", projectID: "prj_1", title: "Do work" } };
      }
      return {};
    });

    const result = await client.callTool({
      name: "create_session",
      arguments: {
        project: "demo",
        prompt: "Do work",
        model: { id: "claude-sonnet-4", providerID: "anthropic" },
      },
    });

    const text = (result.content as Array<{ type: string; text: string }>)[0]?.text ?? "";
    expect(text).toContain("ses_1");
    expect(calls.map((call) => `${call.method} ${call.url}`)).toContain(
      "POST http://127.0.0.1:8787/api/session",
    );
    expect(calls.map((call) => `${call.method} ${call.url}`)).toContain(
      "POST http://127.0.0.1:8787/api/session/ses_1/model",
    );
    expect(calls.map((call) => `${call.method} ${call.url}`)).toContain(
      "POST http://127.0.0.1:8787/api/session/ses_1/prompt",
    );
    expect(calls.find((call) => call.url.endsWith("/prompt"))?.body).toEqual({
      text: "Do work",
    });
  });

  test("sends a scheduled prompt with an attachment", async () => {
    const { client, calls } = await pair();
    const startAt = new Date("2026-01-02T03:04:05Z").toISOString();

    await client.callTool({
      name: "send_prompt",
      arguments: {
        session: "ses_1",
        prompt: "Use this reference",
        delivery: "queue",
        startAt,
        files: [{ uri: "file:///tmp/ref.png" }],
      },
    });

    expect(calls[0]?.body).toEqual({
      text: "Use this reference",
      delivery: "queue",
      startAt: Date.parse(startAt),
      files: [{ uri: "file:///tmp/ref.png" }],
    });
  });

  test("filters tasks by resolved project", async () => {
    const { client, calls } = await pair((call) => {
      if (call.url.endsWith("/api/project")) {
        return [{ id: "prj_1", canonical: "/tmp/demo", sandboxes: [], time: { created: 1, updated: 2 } }];
      }
      return { data: [] };
    });

    await client.callTool({ name: "list_tasks", arguments: { project: "demo" } });
    expect(calls.at(-1)?.url).toContain("/api/task?project=prj_1");
  });

  test("refuses streaming routes in the generic escape hatch", async () => {
    const { client } = await pair();
    const result = await client.callTool({
      name: "hub_request",
      arguments: { path: "/api/terminals/pty_1/socket" },
    });
    expect(result.isError).toBe(true);
  });

  test("forwards a generic API call", async () => {
    const { client, calls } = await pair(() => ({ data: { ok: true } }));
    const result = await client.callTool({
      name: "hub_request",
      arguments: {
        method: "PATCH",
        path: "/api/settings",
        body: { maxConcurrentAgents: 3 },
      },
    });
    expect(result.isError).toBeFalsy();
    expect(calls[0]?.body).toEqual({ maxConcurrentAgents: 3 });
  });
});
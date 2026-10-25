import { describe, expect, test } from "bun:test";
import { HubDB } from "../src/db.ts";
import { OpenCodeError } from "../src/opencode.ts";
import { TerminalService } from "../src/terminals.ts";
import type { Hub } from "../src/hub.ts";
import type { Terminal, TerminalCreateInput } from "../src/types.ts";
import { body, request, setup } from "./helpers/api.ts";

function terminal(overrides: Partial<Terminal> = {}): Terminal {
  return {
    id: "pty_1",
    title: "Build",
    command: "/bin/zsh",
    args: ["-l"],
    cwd: "/tmp/project",
    status: "running",
    pid: 123,
    location: "/tmp/project",
    ...overrides,
  };
}

describe("terminal API", () => {
  test("lists, creates, updates and removes terminals", async () => {
    const created: TerminalCreateInput[] = [];
    const updates: Array<{ id: string; title?: string; location?: string }> = [];
    const removed: Array<{ id: string; location?: string }> = [];
    let items = [terminal()];

    const { handler, db } = setup(
      {},
      {
        terminals: {
          list: async () => items,
          create: async (input) => {
            created.push(input);
            const next = terminal({
              id: "pty_2",
              title: input.title ?? "Terminal",
              cwd: input.cwd ?? "/tmp/project",
              location: input.location ?? "/tmp/project",
            });
            items = [...items, next];
            return next;
          },
          update: async (id, input, location) => {
            updates.push({ id, title: input.title, location });
            return { ...items[0]!, ...(input.title ? { title: input.title } : {}) };
          },
          remove: async (id, location) => {
            removed.push({ id, location });
            items = items.filter((entry) => entry.id !== id);
          },
        },
      },
    );

    const list = await body<{ data: Terminal[] }>(await handler(request("/api/terminals")));
    expect(list.data.map((entry) => entry.id)).toEqual(["pty_1"]);

    const invalid = await handler(
      request("/api/terminals", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ args: [1, 2] }),
      }),
    );
    expect(invalid.status).toBe(400);

    const create = await handler(
      request("/api/terminals", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: "Tests",
          cwd: "/tmp/project",
          location: "/tmp/project",
        }),
      }),
    );
    expect(create.status).toBe(200);
    expect(created[0]).toMatchObject({
      title: "Tests",
      cwd: "/tmp/project",
      location: "/tmp/project",
    });

    const badSize = await handler(
      request("/api/terminals/pty_2", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ size: { rows: 0, cols: 80 } }),
      }),
    );
    expect(badSize.status).toBe(400);

    const update = await handler(
      request("/api/terminals/pty_2", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: "Renamed",
          size: { rows: 24, cols: 80 },
          location: "/tmp/project",
        }),
      }),
    );
    expect(update.status).toBe(200);
    expect(updates[0]).toEqual({
      id: "pty_2",
      title: "Renamed",
      location: "/tmp/project",
    });

    const remove = await handler(
      request("/api/terminals/pty_2?location=%2Ftmp%2Fproject", { method: "DELETE" }),
    );
    expect(remove.status).toBe(200);
    expect(removed).toEqual([{ id: "pty_2", location: "/tmp/project" }]);

    db.close();
  });
});

describe("TerminalService", () => {
  test("merges terminals from the default location and every project", async () => {
    const database = new HubDB(":memory:");
    database.replaceProjects([
      {
        id: "prj_a",
        canonical: "/tmp/a",
        time: { created: 1, updated: 2 },
        sandboxes: ["/tmp/sandbox"],
      },
      {
        id: "prj_b",
        canonical: "/tmp/b",
        time: { created: 1, updated: 2 },
        sandboxes: [],
      },
    ]);

    const calls: Array<string | undefined> = [];
    const client = {
      listPtys: async (directory?: string) => {
        calls.push(directory);
        if (!directory) {
          return {
            location: { directory: "/tmp/home" },
            data: [terminal({ id: "pty_home", location: "/tmp/home" })],
          };
        }
        if (directory === "/tmp/a") {
          return {
            location: { directory },
            data: [
              terminal({ id: "pty_home", location: directory }),
              terminal({ id: "pty_a", title: "A", location: directory }),
            ],
          };
        }
        if (directory === "/tmp/sandbox") {
          return {
            location: { directory },
            data: [terminal({ id: "pty_sandbox", title: "Sandbox", location: directory })],
          };
        }
        throw new OpenCodeError("Location not found", 404);
      },
    };
    const hub = {
      ensureClient: async () => client,
      log: () => {},
    } as unknown as Hub;

    const service = new TerminalService(hub, database);
    const terminals = await service.list(true);

    expect(terminals.map((entry) => entry.id).sort()).toEqual([
      "pty_a",
      "pty_home",
      "pty_sandbox",
    ]);
    expect(terminals.find((entry) => entry.id === "pty_home")?.location).toBe("/tmp/home");
    expect(terminals.find((entry) => entry.id === "pty_a")?.location).toBe("/tmp/a");
    expect(terminals.find((entry) => entry.id === "pty_sandbox")?.location).toBe("/tmp/sandbox");
    expect(calls).toContain("/tmp/a");
    expect(calls).toContain("/tmp/sandbox");
    expect(calls).toContain("/tmp/b");

    database.close();
  });
});

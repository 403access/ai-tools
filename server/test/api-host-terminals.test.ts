import { describe, expect, test } from "bun:test";
import { HostTerminalService } from "../src/host-terminals.ts";
import type { HostTerminal, HostTerminalDetail } from "../src/types.ts";
import { body, request, setup } from "./helpers/api.ts";

function tab(overrides: Partial<HostTerminal> = {}): HostTerminal {
  return {
    id: "ttys001",
    tty: "/dev/ttys001",
    app: "Terminal",
    title: "Shell",
    busy: true,
    processes: ["login", "-zsh"],
    window: 1,
    tab: 1,
    ...overrides,
  };
}

describe("host terminal API", () => {
  test("lists, mirrors and sends commands to Terminal.app tabs", async () => {
    const commands: Array<{ tty: string; command: string }> = [];
    const focused: string[] = [];
    const detail: HostTerminalDetail = {
      ...tab(),
      contents: "echo hello\nhello\n$ ",
      history: "old output\necho hello\nhello\n$ ",
    };

    const { handler, db } = setup(
      {},
      {
        hostTerminals: {
          list: async () => [tab()],
          detail: async (tty, includeHistory) => ({
            ...detail,
            id: tty,
            ...(includeHistory ? {} : { history: undefined }),
          }),
          command: async (tty, command) => {
            commands.push({ tty, command });
          },
          focus: async (tty) => {
            focused.push(tty);
          },
        },
      },
    );

    const list = await body<{ data: HostTerminal[] }>(
      await handler(request("/api/host-terminals")),
    );
    expect(list.data.map((entry) => entry.id)).toEqual(["ttys001"]);

    const one = await body<{ data: HostTerminalDetail }>(
      await handler(request("/api/host-terminals/ttys001")),
    );
    expect(one.data.contents).toContain("hello");
    expect(one.data.history).toBeUndefined();

    const withHistory = await body<{ data: HostTerminalDetail }>(
      await handler(request("/api/host-terminals/ttys001?history=1")),
    );
    expect(withHistory.data.history).toContain("old output");

    const badBody = await handler(
      request("/api/host-terminals/ttys001/command", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ command: 42 }),
      }),
    );
    expect(badBody.status).toBe(400);

    const sent = await handler(
      request("/api/host-terminals/ttys001/command", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ command: "echo hi" }),
      }),
    );
    expect(sent.status).toBe(200);
    expect(commands).toEqual([{ tty: "ttys001", command: "echo hi" }]);

    const focusedResponse = await handler(
      request("/api/host-terminals/ttys001/focus", { method: "POST" }),
    );
    expect(focusedResponse.status).toBe(200);
    expect(focused).toEqual(["ttys001"]);

    db.close();
  });

  test("validates ids and command size before touching macOS automation", async () => {
    const service = new HostTerminalService();

    await expect(service.detail("../etc/passwd")).rejects.toMatchObject({
      status: 400,
    });
    await expect(service.command("ttys001", "x".repeat(20_000))).rejects.toMatchObject({
      status: 413,
    });
  });

  test("reports invalid terminal ids and wrong methods", async () => {
    const { handler, db } = setup(
      {},
      {
        hostTerminals: {
          list: async () => [],
          detail: async () => {
            throw new Error("should not be called");
          },
          command: async () => {},
          focus: async () => {},
        },
      },
    );

    const wrongMethod = await handler(
      request("/api/host-terminals/ttys001", { method: "DELETE" }),
    );
    expect(wrongMethod.status).toBe(405);

    const listWrongMethod = await handler(
      request("/api/host-terminals", { method: "POST" }),
    );
    expect(listWrongMethod.status).toBe(405);

    db.close();
  });
});

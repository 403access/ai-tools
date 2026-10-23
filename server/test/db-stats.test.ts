import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";
import { message, session } from "./helpers/db.ts";

describe("HubDB session stats", () => {
  test("aggregates prompts, tools, failures and file changes", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    db.putMessageSync("ses_1", { syncedAt: 5_000, oldestCursor: null, complete: true });
    db.upsertMessages("ses_1", [
      {
        id: "m1",
        type: "user",
        time: { created: 100 },
        text: "please fix it",
      },
      {
        id: "m2",
        type: "assistant",
        time: { created: 200 },
        content: [
          {
            type: "tool",
            id: "p_shell_1",
            name: "shell",
            state: { status: "completed" },
            time: { ran: 100, completed: 340 },
          },
          {
            type: "tool",
            id: "p_edit_fail",
            name: "edit",
            state: {
              status: "error",
              error: { type: "tool.execution", message: "No changes to apply" },
            },
            time: { ran: 10, completed: 20 },
          },
          {
            type: "tool",
            id: "p_read_running",
            name: "read",
            state: { status: "running" },
            time: { ran: 500 },
          },
        ],
      },
      {
        id: "m3",
        type: "assistant",
        time: { created: 300 },
        content: [
          {
            type: "tool",
            id: "p_edit_ok",
            name: "edit",
            state: {
              status: "completed",
              metadata: {
                files: [{ file: "src/app.ts", patch: "+new", additions: 1, deletions: 1 }],
              },
            },
            time: { ran: 5, completed: 25 },
          },
          {
            type: "tool",
            id: "p_shell_2",
            name: "shell",
            state: { status: "completed" },
            time: { ran: 50, completed: 250 },
          },
        ],
      },
    ]);

    const stats = db.getSessionStats("ses_1");
    expect(stats?.prompts).toBe(1);
    expect(stats?.steps).toBe(2);
    expect(stats?.messages).toBe(3);
    expect(stats?.complete).toBe(true);
    expect(stats?.files).toEqual({ files: 1, additions: 1, deletions: 1 });
    expect(stats?.tools.totals).toEqual({
      calls: 5,
      succeeded: 3,
      failed: 1,
      unfinished: 1,
    });

    const shell = stats?.tools.usage?.find((tool) => tool.name === "shell");
    expect(shell?.calls).toBe(2);
    expect(shell?.durationP50).toBe(220);

    expect(stats?.failures).toHaveLength(1);
    expect(stats?.failures[0]?.name).toBe("edit");
    expect(stats?.failures[0]?.error).toBe("No changes to apply");
    expect(db.getSessionStats("nope")).toBeNull();
    db.close();
  });

  test("keeps only the newest state for a retried tool part", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    const message = (status: string): SessionMessage => ({
      id: "m1",
      type: "assistant",
      time: { created: 100 },
      content: [
        {
          type: "tool",
          id: "p1",
          name: "shell",
          state: { status },
          time: { ran: 10, completed: 50 },
        },
      ],
    });

    db.upsertMessages("ses_1", [message("running")]);
    expect(db.getSessionStats("ses_1")?.tools.totals?.unfinished).toBe(1);
    db.upsertMessages("ses_1", [message("completed")]);
    expect(db.getSessionStats("ses_1")?.tools.totals).toEqual({
      calls: 1,
      succeeded: 1,
      failed: 0,
      unfinished: 0,
    });
    db.close();
  });
});


import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";

function session(overrides: Partial<Session> = {}): Session {
  return {
    id: "ses_1",
    projectID: "prj_1",
    cost: 0.25,
    tokens: { input: 10, output: 20, reasoning: 3, cache: { read: 4, write: 5 } },
    time: { created: 1_000, updated: 2_000 },
    title: "Fix the build",
    location: { directory: "/tmp/project" },
    ...overrides,
  };
}

function message(id: string, created: number): SessionMessage {
  return {
    id,
    type: "assistant",
    time: { created },
    content: [{ type: "text", text: `body ${id}` }],
  };
}

function editMessage(
  id: string,
  created: number,
  files: Array<{ file: string; patch: string; additions?: number; deletions?: number; status?: string }>,
): SessionMessage {
  return {
    id,
    type: "assistant",
    time: { created },
    content: [
      {
        type: "tool",
        id: `part_${id}`,
        name: "edit",
        state: {
          status: "completed",
          metadata: { files },
        },
      },
    ],
  };
}

describe("HubDB sessions", () => {
  test("round-trips sessions and filters by project, parent and active", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([
      session({ title: "Fix the build" }),
      session({ id: "ses_2", projectID: "prj_2", title: "Write docs", time: { created: 500, updated: 3_000 } }),
      session({
        id: "ses_child",
        parentID: "ses_1",
        title: "Search logs",
        time: { created: 600, updated: 1_500 },
      }),
    ]);
    db.setActive(new Set(["ses_2"]));

    expect(db.getSessions().map((s) => s.id)).toEqual(["ses_2", "ses_1", "ses_child"]);
    expect(db.getSessions({ project: "prj_1" }).map((s) => s.id)).toEqual(["ses_1", "ses_child"]);
    expect(db.getSessions({ parentID: "ses_1" }).map((s) => s.id)).toEqual(["ses_child"]);
    expect(db.getSessions({ active: true }).map((s) => s.id)).toEqual(["ses_2"]);
    expect(db.getSessions({ q: "build" }).map((s) => s.id)).toEqual(["ses_1"]);
    db.close();
  });

  test("maps missing token fields to zeroes", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([
      session({
        tokens: undefined as unknown as Session["tokens"],
      }),
    ]);
    expect(db.getSession("ses_1")?.tokens).toEqual({
      input: 0,
      output: 0,
      reasoning: 0,
      cache: { read: 0, write: 0 },
    });
    db.close();
  });

  test("updates live cost and tokens without losing the session", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    db.updateSessionUsage("ses_1", 0.5, {
      input: 1,
      output: 2,
      reasoning: 0,
      cache: { read: 0, write: 0 },
    });
    const updated = db.getSession("ses_1");
    expect(updated?.cost).toBe(0.5);
    expect(updated?.tokens.output).toBe(2);
    db.close();
  });
});

describe("HubDB projects", () => {
  test("replace removes projects that disappeared upstream", () => {
    const db = new HubDB(":memory:");
    const project = {
      id: "prj_1",
      canonical: "/tmp/project",
      time: { created: 1, updated: 2, active: 3 },
      sandboxes: ["/tmp/sandbox"],
    };
    db.replaceProjects([project]);
    expect(db.getProjects()).toEqual([project]);
    db.replaceProjects([]);
    expect(db.getProjects()).toEqual([]);
    db.close();
  });
});

describe("HubDB messages", () => {
  test("upserts and pages newest first with the hub cursor", () => {
    const db = new HubDB(":memory:");
    db.upsertMessages("ses_1", [
      message("m1", 100),
      message("m2", 200),
      message("m3", 300),
      message("m4", 400),
    ]);

    const first = db.getMessages("ses_1", 2);
    expect(first.data.map((m) => m.id)).toEqual(["m4", "m3"]);
    expect(first.cursor?.next).toBeTruthy();

    const second = db.getMessages("ses_1", 2, first.cursor?.next);
    expect(second.data.map((m) => m.id)).toEqual(["m2", "m1"]);
    expect(second.cursor?.next).toBeUndefined();

    const decoded = decodeMessageCursor(first.cursor!.next!);
    expect(decoded?.i).toBe("m3");
    expect(encodeMessageCursor(message("x", 1)).startsWith("hub.")).toBe(true);
    db.close();
  });

  test("keeps existing content when a streaming update has no body", () => {
    const db = new HubDB(":memory:");
    db.upsertMessages("ses_1", [message("m1", 100)]);
    db.upsertMessages("ses_1", [{ id: "m1", type: "assistant", time: { created: 100 } }]);
    const page = db.getMessages("ses_1", 10);
    expect(page.data[0]?.content).toEqual([{ type: "text", text: "body m1" }]);
    db.close();
  });
});

describe("HubDB changes", () => {
  test("extracts patches from edit tool metadata", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([
      session(),
      session({ id: "ses_2", projectID: "prj_2", title: "Other project" }),
    ]);
    db.upsertMessages("ses_1", [
      editMessage("m1", 100, [
        {
          file: "Sources/App.swift",
          patch: "--- a/Sources/App.swift\n+++ b/Sources/App.swift\n@@ -1 +1 @@\n-old\n+new\n",
          additions: 1,
          deletions: 1,
          status: "modified",
        },
      ]),
      editMessage("m2", 200, [
        {
          file: "README.md",
          patch: "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-a\n+b\n",
          additions: 1,
          deletions: 1,
          status: "modified",
        },
        {
          file: "docs/new.md",
          patch: "--- /dev/null\n+++ b/docs/new.md\n@@ -0,0 +1 @@\n+hello\n",
          additions: 1,
          deletions: 0,
          status: "added",
        },
      ]),
    ]);
    db.upsertMessages("ses_2", [
      editMessage("m3", 300, [
        { file: "Other.swift", patch: "+other\n", additions: 1, deletions: 0, status: "added" },
      ]),
    ]);

    const sessionChanges = db.getChanges("ses_1");
    expect(sessionChanges.map((c) => c.file)).toEqual([
      "README.md",
      "docs/new.md",
      "Sources/App.swift",
    ]);
    expect(sessionChanges[0]?.additions).toBe(1);

    const projectChanges = db.getProjectChanges("prj_1");
    expect(projectChanges.map((c) => c.file)).toEqual([
      "README.md",
      "docs/new.md",
      "Sources/App.swift",
    ]);
    expect(projectChanges[0]?.sessionID).toBe("ses_1");
    expect(projectChanges[0]?.sessionTitle).toBe("Fix the build");
    expect(db.getProjectChanges("prj_2").map((c) => c.file)).toEqual(["Other.swift"]);
    db.close();
  });

  test("synthesizes a patch for write tool calls", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session({ location: { directory: "/tmp/project" } })]);
    db.upsertMessages("ses_1", [
      {
        id: "m1",
        type: "assistant",
        time: { created: 100 },
        content: [
          {
            type: "tool",
            id: "part_write",
            name: "write",
            state: {
              status: "completed",
              input: {
                path: "/tmp/project/src/new.ts",
                content: "line one\nline two\n",
              },
              metadata: { truncated: false },
            },
          },
        ],
      },
    ]);

    const changes = db.getChanges("ses_1");
    expect(changes).toHaveLength(1);
    expect(changes[0]?.file).toBe("src/new.ts");
    expect(changes[0]?.status).toBe("added");
    expect(changes[0]?.additions).toBe(2);
    expect(changes[0]?.patch).toContain("+line one");
    db.close();
  });

  test("keeps the newest patch when a message is updated", () => {
    const db = new HubDB(":memory:");
    db.upsertSessions([session()]);
    db.upsertMessages("ses_1", [
      editMessage("m1", 100, [{ file: "a.txt", patch: "one", additions: 1, deletions: 0 }]),
    ]);
    db.upsertMessages("ses_1", [
      editMessage("m1", 100, [{ file: "a.txt", patch: "two", additions: 2, deletions: 0 }]),
    ]);
    const changes = db.getChanges("ses_1");
    expect(changes).toHaveLength(1);
    expect(changes[0]?.patch).toBe("two");
    expect(changes[0]?.additions).toBe(2);
    db.close();
  });
});

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

describe("HubDB stats and usage", () => {
  test("caches stats per scope", () => {
    const db = new HubDB(":memory:");
    db.putStats("__global__", { steps: 10, activity: [{ date: "2026-10-21", steps: 10 }] });
    db.putStats("prj_1", { steps: 4 });
    expect(db.getStats("__global__")?.data.steps).toBe(10);
    expect(db.getStats("prj_1")?.data.steps).toBe(4);
    expect(db.getStats("nope")).toBeNull();
    db.close();
  });

  test("keeps the last usage payload when a refresh fails", () => {
    const db = new HubDB(":memory:");
    db.putUsage({ rolling: { percent: 42 } }, 1_000, null, 1_000);
    db.putUsageError("key expired", 2_000);
    const usage = db.getUsage();
    expect(usage.data?.rolling?.percent).toBe(42);
    expect(usage.fetchedAt).toBe(1_000);
    expect(usage.error).toBe("key expired");
    db.close();
  });
});

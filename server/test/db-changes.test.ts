import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../src/db.ts";
import type { Session, SessionMessage } from "../src/types.ts";
import { editMessage, session } from "./helpers/db.ts";

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


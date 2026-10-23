import { describe, expect, test } from "bun:test";
import { HubDB, decodeMessageCursor, encodeMessageCursor } from "../../src/db.ts";
import type { Session, SessionMessage } from "../../src/types.ts";

export function session(overrides: Partial<Session> = {}): Session {
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

export function message(id: string, created: number): SessionMessage {
  return {
    id,
    type: "assistant",
    time: { created },
    content: [{ type: "text", text: `body ${id}` }],
  };
}

export function editMessage(
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


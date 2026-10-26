import { describe, expect, test } from "bun:test";
import { classifyTaskLabels } from "../src/db/taskLabels.ts";
import type { Session } from "../src/types.ts";
import { body, request, session, setup, type SessionList } from "./helpers/api.ts";

function taskSession(overrides: Partial<Session> = {}): Session {
  const now = Date.now();
  return session(`ses_task_${Math.random().toString(36).slice(2)}`, now, {
    time: { created: now, updated: now },
    title: "Fix the crash on the settings page",
    ...overrides,
  });
}

describe("task board", () => {
  test("classifies common requests into a few useful labels", () => {
    expect(classifyTaskLabels("Fix the crash when saving", "")).toEqual([
      { id: "bug", title: "Bug", kind: "type" },
    ]);

    const product = classifyTaskLabels("Add a search box to the settings page", "");
    expect(product.find((label) => label.id === "feature")).toBeDefined();
    expect(product.find((label) => label.id === "product")).toBeDefined();

    const security = classifyTaskLabels("Fix authentication token leak", "");
    expect(security[0]?.id).toBe("security");
    expect(security.some((label) => label.id === "security-sensitive")).toBe(false);

    const docs = classifyTaskLabels("Update the README docs", "");
    expect(docs.find((label) => label.id === "docs")).toBeDefined();
    expect(docs.find((label) => label.id === "technical")).toBeDefined();

    expect(classifyTaskLabels("", "")).toEqual([]);
  });

  test("only tracks new top-level sessions and exposes review state", async () => {
    const { db, handler } = setup();
    const now = Date.now();
    const task = taskSession();

    db.upsertSessions([
      task,
      session("ses_old", now, { time: { created: 1, updated: now } }),
      taskSession({ id: "ses_child", parentID: "ses_parent" }),
    ]);

    const response = await handler(request("/api/task"));
    expect(response.status).toBe(200);
    const list = await body<SessionList>(response);
    expect(list.data.map((item) => item.id)).toEqual([task.id]);
    const tracked = list.data[0]!;
    expect(tracked.task?.status).toBe("review");
    expect(tracked.task?.labels.map((label) => label.id)).toContain("bug");

    db.close();
  });

  test("marks done, reopens, and dismisses a task", async () => {
    const { db, handler } = setup();
    const task = taskSession();
    db.upsertSessions([task]);

    const done = await handler(
      request(`/api/task/${task.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: "done" }),
      }),
    );
    expect(done.status).toBe(200);
    expect((await body<{ data: Session }>(done)).data.task?.status).toBe("done");

    const reopened = await handler(
      request(`/api/task/${task.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: "open" }),
      }),
    );
    expect((await body<{ data: Session }>(reopened)).data.task?.status).toBe("review");

    const dismissed = await handler(
      request(`/api/task/${task.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: "dismissed" }),
      }),
    );
    expect((await body<{ data: Session }>(dismissed)).data.task?.status).toBe("dismissed");

    const invalid = await handler(
      request(`/api/task/${task.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: "maybe" }),
      }),
    );
    expect(invalid.status).toBe(400);

    const missing = await handler(
      request("/api/task/does-not-exist", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: "done" }),
      }),
    );
    expect(missing.status).toBe(404);

    db.close();
  });

  test("running sessions are working and new prompt text reopens done tasks", () => {
    const { db } = setup();
    const task = taskSession({ title: "Fix the login crash" });
    db.upsertSessions([task]);
    db.setActive(new Set([task.id]));

    expect(db.getSession(task.id)?.task?.status).toBe("working");

    db.markActive(task.id, false);
    db.setTaskStatus(task.id, "done");
    expect(db.getSession(task.id)?.task?.status).toBe("done");

    // Prompts arrive through the hub; the stored context refines the labels and
    // the task returns to review.
    db.recordTaskPrompt(task.id, "Also add a regression test for the timeout");
    db.markActive(task.id, true);
    const updated = db.getSession(task.id)!;
    expect(updated.task?.status).toBe("working");
    expect(updated.task?.labels.map((label) => label.id)).toContain("bug");

    db.close();
  });
});

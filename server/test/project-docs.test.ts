import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ProjectDocumentation } from "../src/types.ts";
import { summarizeReadme } from "../src/projectDocs.ts";
import { body, request, session, setup } from "./helpers/api.ts";

function project(id: string, canonical: string) {
  return {
    id,
    canonical,
    time: { created: 1, updated: 2 },
    sandboxes: [],
  };
}

describe("project documentation", () => {
  test("summarizes the opening README paragraph and skips badges", () => {
    expect(
      summarizeReadme(
        [
          "# OpenCodeBar",
          "",
          "[![Build](https://example.invalid/badge.svg)](https://example.invalid)",
          "",
          "A menu bar app and iOS client for **OpenCode** that shows sessions,",
          "projects, and usage at a glance.",
          "",
          "## Install",
        ].join("\n"),
      ),
    ).toBe("A menu bar app and iOS client for OpenCode that shows sessions, projects, and usage at a glance.");
  });

  test("turns prompts into product and technical entries with task references", () => {
    const { db } = setup();
    const now = Date.now();
    const productTask = session("ses_product", now, {
      title: "Add a search box to the settings page",
      location: { directory: "/tmp/project" },
    });
    const technicalTask = session("ses_technical", now, {
      title: "Refactor the database schema",
      location: { directory: "/tmp/project" },
    });
    const removedTask = session("ses_remove", now, {
      title: "Remove the old API endpoint",
      location: { directory: "/tmp/project" },
    });

    db.upsertSessions([productTask, technicalTask, removedTask]);
    db.createProjectDocumentation("prj_1", "A test project.");

    db.recordTaskPrompt(productTask.id, "Add a search box to the settings page");
    db.recordTaskPrompt(technicalTask.id, "Refactor the database schema");
    db.recordTaskPrompt(removedTask.id, "Remove the old API endpoint");

    const docs = db.getProjectDocumentation("prj_1")!;
    expect(docs.description).toBe("A test project.");
    expect(docs.productFeatures).toHaveLength(1);
    expect(docs.technicalFeatures).toHaveLength(2);

    const product = docs.productFeatures[0]!;
    expect(product.kind).toBe("product");
    expect(product.action).toBe("new");
    expect(product.category).toBe("feature");
    expect(product.sessionID).toBe(productTask.id);
    expect(product.taskTitle).toBe("Add a search box to the settings page");
    expect(product.labels.some((label) => label.id === "product")).toBe(true);

    const refactor = docs.technicalFeatures.find((entry) => entry.sessionID === technicalTask.id)!;
    expect(refactor.kind).toBe("technical");
    expect(refactor.action).toBe("update");
    expect(refactor.category).toBe("refactor");

    const removed = docs.technicalFeatures.find((entry) => entry.sessionID === removedTask.id)!;
    expect(removed.action).toBe("remove");
    db.close();
  });

  test("records a queued prompt once when it is later sent", () => {
    const { db } = setup();
    const now = Date.now();
    const task = session("ses_queued", now, {
      title: "Add a project Docs tab",
      location: { directory: "/tmp/project" },
    });
    db.upsertSessions([task]);
    db.createProjectDocumentation("prj_1");

    db.recordTaskPrompt(task.id, "Add a project Docs tab");
    db.recordTaskPrompt(task.id, "Add a project Docs tab");

    const docs = db.getProjectDocumentation("prj_1")!;
    expect(docs.productFeatures).toHaveLength(1);
    expect(docs.productFeatures[0]?.action).toBe("new");
    db.close();
  });

  test("ignores subagent prompts and internal continuations", () => {
    const { db } = setup();
    const now = Date.now();
    const child = session("ses_child", now, {
      parentID: "ses_parent",
      title: "Add a helper",
    });
    const task = session("ses_task", now, { title: "Add a helper" });
    db.upsertSessions([child, task]);
    db.createProjectDocumentation("prj_1");

    db.recordTaskPrompt(child.id, "Add a helper");
    db.recordTaskPrompt(task.id, "continue");

    const docs = db.getProjectDocumentation("prj_1")!;
    expect(docs.productFeatures.length + docs.technicalFeatures.length).toBe(0);
    db.close();
  });

  test("serves and edits the brief over the API", async () => {
    const directory = mkdtempSync(join(tmpdir(), "opencodebar-docs-"));
    writeFileSync(
      join(directory, "README.md"),
      "# Test project\n\nA project that keeps its own living product record.\n",
    );

    const { db, handler } = setup();
    db.replaceProjects([project("prj_docs", directory)]);
    const now = Date.now();
    const task = session("ses_docs", now, {
      projectID: "prj_docs",
      title: "Add a documentation page",
      location: { directory },
    });
    db.upsertSessions([task]);
    db.recordTaskPrompt(task.id, "Add a documentation page");

    try {
      const response = await handler(request("/api/project/prj_docs/docs"));
      expect(response.status).toBe(200);
      const initial = await body<{ data: ProjectDocumentation }>(response);
      expect(initial.data.description).toBe(
        "A project that keeps its own living product record.",
      );
      expect(initial.data.productFeatures[0]?.sessionID).toBe(task.id);

      const updated = await handler(
        request("/api/project/prj_docs/docs", {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            mission: "Make the project legible.",
            vision: "Every change has a home.",
          }),
        }),
      );
      expect(updated.status).toBe(200);
      const edited = await body<{ data: ProjectDocumentation }>(updated);
      expect(edited.data.description).toBe(
        "A project that keeps its own living product record.",
      );
      expect(edited.data.mission).toBe("Make the project legible.");
      expect(edited.data.vision).toBe("Every change has a home.");

      const invalid = await handler(
        request("/api/project/prj_docs/docs", {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ mission: 42 }),
        }),
      );
      expect(invalid.status).toBe(400);

      expect(
        (await handler(request("/api/project/prj_docs/docs", { method: "POST" }))).status,
      ).toBe(405);
      expect((await handler(request("/api/project/missing/docs"))).status).toBe(404);
    } finally {
      rmSync(directory, { recursive: true, force: true });
      db.close();
    }
  });
});

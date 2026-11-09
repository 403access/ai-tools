import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readProjectScripts } from "../src/scripts.ts";
import type { ProjectScripts } from "../src/types.ts";
import { body, request, setup } from "./helpers/api.ts";

function projectDir(): string {
  return mkdtempSync(join(tmpdir(), "opencodebar-scripts-"));
}

describe("project scripts", () => {
  test("reads the manifests a project exposes", () => {
    const directory = projectDir();
    try {
      writeFileSync(
        join(directory, "package.json"),
        JSON.stringify({
          packageManager: "pnpm@9.1.0",
          scripts: {
            dev: "vite dev",
            build: "vite build",
          },
        }),
      );
      writeFileSync(
        join(directory, "Makefile"),
        [
          ".PHONY: build test",
          "",
          "# Build the app bundle.",
          "build:",
          "\tswift build",
          "",
          "test: build ## Run the test suite.",
          "\tswift test",
          "",
          "VAR := value",
        ].join("\n"),
      );
      writeFileSync(
        join(directory, "justfile"),
        ["# Format sources.", "format:", "  swift format", "", "set shell := [\"bash\"]"].join("\n"),
      );
      writeFileSync(
        join(directory, "composer.json"),
        JSON.stringify({ scripts: { serve: "php -S localhost:8000" } }),
      );

      const result = readProjectScripts(directory);
      expect(result.scripts).toEqual([
        {
          name: "dev",
          command: "pnpm run dev",
          source: "package.json",
          tool: "pnpm",
          detail: "vite dev",
        },
        {
          name: "build",
          command: "pnpm run build",
          source: "package.json",
          tool: "pnpm",
          detail: "vite build",
        },
        {
          name: "build",
          command: "make build",
          source: "Makefile",
          tool: "make",
          description: "Build the app bundle.",
        },
        {
          name: "test",
          command: "make test",
          source: "Makefile",
          tool: "make",
          description: "Run the test suite.",
        },
        {
          name: "format",
          command: "just format",
          source: "justfile",
          tool: "just",
          description: "Format sources.",
        },
        {
          name: "serve",
          command: "composer run serve",
          source: "composer.json",
          tool: "composer",
          detail: "php -S localhost:8000",
        },
      ]);
      expect(result.generatedAt).toBeGreaterThan(0);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("returns an empty list when the project has no manifests", () => {
    const directory = projectDir();
    try {
      expect(readProjectScripts(directory).scripts).toEqual([]);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("serves scripts for a project", async () => {
    const directory = projectDir();
    const { db, handler } = setup();
    try {
      mkdirSync(directory, { recursive: true });
      writeFileSync(
        join(directory, "package.json"),
        JSON.stringify({ scripts: { test: "bun test" } }),
      );
      db.replaceProjects([
        {
          id: "prj_scripts",
          canonical: directory,
          time: { created: 1, updated: 2 },
          sandboxes: [],
        },
      ]);

      const response = await handler(request("/api/project/prj_scripts/scripts"));
      expect(response.status).toBe(200);
      const result = await body<{ data: ProjectScripts }>(response);
      expect(result.data.scripts).toEqual([
        {
          name: "test",
          command: "npm run test",
          source: "package.json",
          tool: "npm",
          detail: "bun test",
        },
      ]);

      expect(
        (await handler(request("/api/project/prj_scripts/scripts", { method: "POST" }))).status,
      ).toBe(405);
      expect((await handler(request("/api/project/nope/scripts"))).status).toBe(404);
    } finally {
      db.close();
      rmSync(directory, { recursive: true, force: true });
    }
  });
});

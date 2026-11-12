import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import type { Project } from "../src/types.ts";
import {
  deriveTitle,
  discoverHub,
  HubClient,
  HubError,
  projectDisplayName,
  resolveProject,
} from "../src/mcp/hub.ts";

function project(overrides: Partial<Project> & Pick<Project, "id" | "canonical">): Project {
  return {
    vcs: "git",
    sandboxes: [],
    time: { created: 1_000, updated: 2_000 },
    ...overrides,
  };
}

const aiTools = project({ id: "prj_ai_tools", canonical: "/Users/me/Developer/ai-tools" });
const mobile = project({ id: "prj_mobile", canonical: "/Users/me/Developer/opencodebar-mobile" });
const website = project({
  id: "prj_website",
  canonical: "/Users/me/Work/website",
  name: "Marketing Website",
  time: { created: 1_000, updated: 5_000 },
});

describe("projectDisplayName", () => {
  test("prefers the project name", () => {
    expect(projectDisplayName(website)).toBe("Marketing Website");
  });

  test("falls back to the checkout folder", () => {
    expect(projectDisplayName(aiTools)).toBe("ai-tools");
  });
});

describe("resolveProject", () => {
  const projects = [aiTools, mobile, website];

  test("matches the folder name", () => {
    const result = resolveProject(projects, "ai-tools");
    expect("project" in result && result.project.id).toBe("prj_ai_tools");
  });

  test("matches a display name case-insensitively", () => {
    const result = resolveProject(projects, "marketing website");
    expect("project" in result && result.project.id).toBe("prj_website");
  });

  test("matches an exact path", () => {
    const result = resolveProject(projects, "/Users/me/Developer/opencodebar-mobile/");
    expect("project" in result && result.project.id).toBe("prj_mobile");
  });

  test("matches a home-relative path", () => {
    const homeProject = project({
      id: "prj_home",
      canonical: join(homedir(), "Developer", "ai-tools"),
    });
    const result = resolveProject([homeProject], "~/Developer/ai-tools");
    expect("project" in result && result.project.id).toBe("prj_home");
  });

  test("matches the project id", () => {
    const result = resolveProject(projects, "prj_mobile");
    expect("project" in result && result.project.id).toBe("prj_mobile");
  });

  test("treats duplicate rows for the same checkout as one project", () => {
    const gitRow = project({
      id: "prj_git",
      canonical: "/Users/me/Developer/ai-tools",
      time: { created: 1_000, updated: 4_000 },
    });
    const nonGitRow = project({
      id: "prj_plain",
      canonical: "/Users/me/Developer/ai-tools",
      vcs: undefined,
      time: { created: 1_000, updated: 2_000 },
    });
    const result = resolveProject([nonGitRow, gitRow], "ai-tools");
    expect("project" in result && result.project.id).toBe("prj_git");
  });

  test("returns candidates instead of guessing between equal matches", () => {
    const first = project({ id: "prj_one", canonical: "/a/tools" });
    const second = project({ id: "prj_two", canonical: "/b/tools" });
    const result = resolveProject([first, second], "tools");
    expect("candidates" in result && result.candidates.map((value) => value.id)).toEqual([
      "prj_one",
      "prj_two",
    ]);
  });

  test("reports an unknown project", () => {
    const result = resolveProject(projects, "nothing-like-this");
    expect("error" in result && result.error).toContain("No project matches");
  });

  test("rejects an empty query", () => {
    const result = resolveProject(projects, "   ");
    expect("error" in result).toBe(true);
  });
});

describe("deriveTitle", () => {
  test("uses the first non-empty line without markdown heading marks", () => {
    expect(deriveTitle("\n## Add a command bar\nMore detail")).toBe("Add a command bar");
  });

  test("truncates long lines", () => {
    const title = deriveTitle("a".repeat(200), 20);
    expect(title?.length).toBe(20);
    expect(title?.endsWith("…")).toBe(true);
  });

  test("returns undefined for blank prompts", () => {
    expect(deriveTitle(" \n ")).toBeUndefined();
  });
});

describe("discoverHub", () => {
  test("reads the hub's pairing file", () => {
    const directory = mkdtempSync(join(tmpdir(), "opencodebar-mcp-"));
    try {
      const config = join(directory, "opencode");
      mkdirSync(config, { recursive: true });
      writeFileSync(
        join(config, "opencodebar-hub.json"),
        JSON.stringify({ url: "http://127.0.0.1:9000/", token: "paired-token" }),
      );

      const location = discoverHub({ XDG_CONFIG_HOME: directory });
      expect(location).toEqual({ url: "http://127.0.0.1:9000", token: "paired-token" });
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("environment values override the pairing file", () => {
    const directory = mkdtempSync(join(tmpdir(), "opencodebar-mcp-"));
    try {
      const config = join(directory, "opencode");
      mkdirSync(config, { recursive: true });
      writeFileSync(
        join(config, "opencodebar-hub.json"),
        JSON.stringify({ url: "http://127.0.0.1:9000", token: "paired-token" }),
      );

      const location = discoverHub({
        XDG_CONFIG_HOME: directory,
        OPENCODEBAR_HUB_URL: "https://hub.example.test",
        OPENCODEBAR_HUB_TOKEN: "env-token",
      });
      expect(location).toEqual({ url: "https://hub.example.test", token: "env-token" });
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("explains how to start the hub when there is no token", () => {
    const directory = mkdtempSync(join(tmpdir(), "opencodebar-mcp-"));
    try {
      expect(() => discoverHub({ XDG_CONFIG_HOME: directory })).toThrow(HubError);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});

describe("HubClient", () => {
  test("creates a session in the project directory", async () => {
    const calls: Array<{ url: string; init: RequestInit | undefined }> = [];
    const fetchImpl = (async (input: string | URL | Request, init?: RequestInit) => {
      calls.push({ url: String(input), init });
      return new Response(
        JSON.stringify({ data: { id: "ses_1", projectID: "prj_1", cost: 0, tokens: {} } }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }) as typeof fetch;

    const hub = new HubClient({ url: "http://127.0.0.1:8787", token: "secret" }, fetchImpl);
    const session = await hub.createSession({
      title: "Add the thing",
      directory: "/tmp/project",
    });

    expect(session.id).toBe("ses_1");
    expect(calls).toHaveLength(1);
    expect(calls[0]?.url).toBe("http://127.0.0.1:8787/api/session");
    expect(calls[0]?.init?.method).toBe("POST");
    expect(new Headers(calls[0]?.init?.headers).get("authorization")).toBe("Bearer secret");
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      title: "Add the thing",
      location: { directory: "/tmp/project" },
    });
  });

  test("surfaces the hub's error message", async () => {
    const fetchImpl = (async () =>
      new Response(JSON.stringify({ error: { message: "OpenCode is offline" } }), {
        status: 503,
      })) as unknown as typeof fetch;

    const hub = new HubClient({ url: "http://127.0.0.1:8787", token: "secret" }, fetchImpl);
    await expect(hub.session("ses_1")).rejects.toThrow("OpenCode is offline");
  });

  test("explains a missing hub", async () => {
    const fetchImpl = (async () => {
      throw new Error("connect ECONNREFUSED");
    }) as unknown as typeof fetch;

    const hub = new HubClient({ url: "http://127.0.0.1:8787", token: "secret" }, fetchImpl);
    await expect(hub.projects()).rejects.toThrow("Could not reach the OpenCodeBar hub");
  });
});

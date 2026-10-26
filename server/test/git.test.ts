import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  parseGitBranches,
  parseGitLog,
  readProjectGit,
  readSessionGit,
} from "../src/git.ts";
import { body, request, session, setup } from "./helpers/api.ts";

const directories: string[] = [];

function tempDirectory(): string {
  const directory = mkdtempSync(join(tmpdir(), "opencodebar-git-"));
  directories.push(directory);
  return directory;
}

function git(directory: string, date: string, ...args: string[]): string {
  const result = Bun.spawnSync(["git", "-C", directory, ...args], {
    stdout: "pipe",
    stderr: "pipe",
    env: {
      ...process.env,
      GIT_AUTHOR_DATE: date,
      GIT_COMMITTER_DATE: date,
      GIT_AUTHOR_NAME: "OpenCodeBar Test",
      GIT_AUTHOR_EMAIL: "test@example.com",
      GIT_COMMITTER_NAME: "OpenCodeBar Test",
      GIT_COMMITTER_EMAIL: "test@example.com",
    },
  });
  if (result.exitCode !== 0) {
    throw new Error(result.stderr.toString() || `git ${args.join(" ")} failed`);
  }
  return result.stdout.toString();
}

function commit(directory: string, date: string, file: string, contents: string, message: string): void {
  writeFileSync(join(directory, file), contents);
  git(directory, date, "add", file);
  git(directory, date, "commit", "-q", "-m", message);
}

const gitAvailable =
  Bun.spawnSync(["git", "--version"], { stdout: "ignore", stderr: "ignore" }).exitCode === 0;

afterEach(() => {
  while (directories.length) {
    rmSync(directories.pop()!, { recursive: true, force: true });
  }
});

describe("git parsers", () => {
  test("reads commit records including parents and decorations", () => {
    const record = [
      "abc123",
      "abc123",
      "def456 ghi789",
      "Ada",
      "ada@example.com",
      "1700000000",
      "Ada",
      "ada@example.com",
      "1700000001",
      "HEAD -> main, tag: v1",
      "Add the thing",
    ].join("\x1f");
    const [parsed] = parseGitLog(`${record}\x1e`);

    expect(parsed?.hash).toBe("abc123");
    expect(parsed?.parents).toEqual(["def456", "ghi789"]);
    expect(parsed?.author.time).toBe(1_700_000_000_000);
    expect(parsed?.refs).toEqual(["HEAD -> main", "tag: v1"]);
    expect(parsed?.subject).toBe("Add the thing");
  });

  test("marks the current branch and parses tracking offsets", () => {
    const output = [
      ["main", "abc", "origin/main", "[ahead 2, behind 1]"].join("\x1f"),
      ["feature", "def", "", ""].join("\x1f"),
    ].join("\n");
    const branches = parseGitBranches(output, "main");

    expect(branches[0]).toMatchObject({
      name: "main",
      current: true,
      upstream: "origin/main",
      ahead: 2,
      behind: 1,
    });
    expect(branches[1]).toMatchObject({ name: "feature", current: false, ahead: 0, behind: 0 });
    expect(branches[1]?.upstream).toBeUndefined();
  });
});

describe("repository reads", () => {
  test("reports a file folder as having no repository", async () => {
    const directory = tempDirectory();
    expect(await readProjectGit(directory)).toBeNull();
    const session = await readSessionGit(directory, 1, 2);
    expect(session.repository).toBeNull();
    expect(session.commits).toEqual([]);
  });

  test.skipIf(!gitAvailable)("reads the full project tree and a session window", async () => {
    const directory = tempDirectory();
    git(directory, "2026-01-01T10:00:00Z", "init", "-q", "-b", "main");

    commit(directory, "2026-01-01T10:00:00Z", "a.txt", "a\n", "first");
    commit(directory, "2026-01-01T11:00:00Z", "b.txt", "b\n", "second");
    git(directory, "2026-01-01T11:00:00Z", "tag", "v1");
    git(directory, "2026-01-01T12:00:00Z", "checkout", "-q", "-b", "feature");
    commit(directory, "2026-01-01T12:00:00Z", "c.txt", "c\n", "feature work");
    git(directory, "2026-01-01T13:00:00Z", "checkout", "-q", "main");
    commit(directory, "2026-01-01T13:00:00Z", "d.txt", "d\n", "main work");
    writeFileSync(join(directory, "dirty.txt"), "not committed\n");

    const project = await readProjectGit(directory, 100);
    expect(project).not.toBeNull();
    expect(project?.root).toBe(realpathSync(directory));
    expect(project?.branch).toBe("main");
    expect(project?.head?.subject).toBe("main work");
    expect(project?.dirty).toBe(1);
    expect(project?.tags).toEqual(["v1"]);
    expect(project?.branches.map((branch) => branch.name).sort()).toEqual(["feature", "main"]);
    expect(project?.branches.find((branch) => branch.name === "main")?.current).toBe(true);
    expect(project?.total).toBe(4);
    expect(project?.commits).toHaveLength(4);
    expect(project?.truncated).toBe(false);

    const session = await readSessionGit(
      directory,
      Date.parse("2026-01-01T10:30:00Z"),
      Date.parse("2026-01-01T11:30:00Z"),
      100,
    );
    expect(session.repository?.branch).toBe("main");
    expect(session.repository?.head?.subject).toBe("main work");
    expect(session.commits.map((entry) => entry.subject)).toEqual(["second"]);
    expect(session.total).toBe(1);

    const quiet = await readSessionGit(
      directory,
      Date.parse("2026-01-01T14:00:00Z"),
      Date.parse("2026-01-01T15:00:00Z"),
      100,
    );
    expect(quiet.commits).toEqual([]);
    expect(quiet.repository?.branch).toBe("main");
  });

  test.skipIf(!gitAvailable)("serves project and session git endpoints", async () => {
    const directory = tempDirectory();
    git(directory, "2026-01-01T10:00:00Z", "init", "-q", "-b", "main");
    commit(directory, "2026-01-01T10:00:00Z", "a.txt", "a\n", "first");
    commit(directory, "2026-01-01T11:00:00Z", "b.txt", "b\n", "second");

    const { db, handler } = setup();
    db.replaceProjects([
      {
        id: "prj_git",
        canonical: directory,
        time: { created: 1, updated: 2 },
        sandboxes: [],
      },
    ]);
    db.upsertSessions([
      session("ses_git", Date.parse("2026-01-01T11:30:00Z"), {
        projectID: "prj_git",
        time: {
          created: Date.parse("2026-01-01T10:30:00Z"),
          updated: Date.parse("2026-01-01T11:30:00Z"),
        },
        location: { directory },
      }),
    ]);

    try {
      const projectResponse = await handler(request("/api/project/prj_git/git?limit=10"));
      expect(projectResponse.status).toBe(200);
      const project = await body<{
        data: { branch: string; commits: Array<{ subject: string }>; total: number } | null;
      }>(projectResponse);
      expect(project.data?.branch).toBe("main");
      expect(project.data?.commits.map((commit) => commit.subject)).toEqual(["second", "first"]);
      expect(project.data?.total).toBe(2);

      const sessionResponse = await handler(request("/api/session/ses_git/git"));
      expect(sessionResponse.status).toBe(200);
      const git = await body<{
        data: { repository: { branch: string } | null; commits: Array<{ subject: string }> };
      }>(sessionResponse);
      expect(git.data.repository?.branch).toBe("main");
      expect(git.data.commits.map((commit) => commit.subject)).toEqual(["second"]);

      expect((await handler(request("/api/project/nope/git"))).status).toBe(404);
      expect((await handler(request("/api/session/nope/git"))).status).toBe(404);
    } finally {
      db.close();
    }
  });

  test.skipIf(!gitAvailable)("caps a large project response and reports the full total", async () => {
    const directory = tempDirectory();
    git(directory, "2026-01-01T10:00:00Z", "init", "-q", "-b", "main");
    commit(directory, "2026-01-01T10:00:00Z", "a.txt", "a\n", "first");
    commit(directory, "2026-01-01T11:00:00Z", "b.txt", "b\n", "second");

    const project = await readProjectGit(directory, 1);
    expect(project?.commits).toHaveLength(1);
    expect(project?.total).toBe(2);
    expect(project?.truncated).toBe(true);
  });
});

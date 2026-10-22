import { afterEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { listProjectFiles, parseGitStatus } from "../src/files.ts";

const directories: string[] = [];

function tempDirectory(): string {
  const directory = mkdtempSync(join(tmpdir(), "opencodebar-files-"));
  directories.push(directory);
  return directory;
}

function git(directory: string, ...args: string[]): string {
  const result = Bun.spawnSync(["git", "-C", directory, ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    throw new Error(result.stderr.toString() || `git ${args.join(" ")} failed`);
  }
  return result.stdout.toString();
}

const gitAvailable =
  Bun.spawnSync(["git", "--version"], { stdout: "ignore", stderr: "ignore" }).exitCode === 0;

afterEach(() => {
  while (directories.length) {
    rmSync(directories.pop()!, { recursive: true, force: true });
  }
});

describe("parseGitStatus", () => {
  test("maps porcelain codes onto the file statuses the clients show", () => {
    const statuses = parseGitStatus(
      [
        " M src/app.ts",
        "A  src/new.ts",
        " D src/old.ts",
        "?? notes.md",
        "R  src/before.ts\0src/after.ts",
        "!! ignored.log",
      ].join("\0") + "\0",
    );

    expect(statuses.get("src/app.ts")).toBe("modified");
    expect(statuses.get("src/new.ts")).toBe("added");
    expect(statuses.get("src/old.ts")).toBe("deleted");
    expect(statuses.get("notes.md")).toBe("added");
    expect(statuses.has("ignored.log")).toBe(false);
  });
});

describe("listProjectFiles", () => {
  test("walks a folder that is not a git work tree", async () => {
    const directory = tempDirectory();
    mkdirSync(join(directory, "src"));
    mkdirSync(join(directory, "node_modules"));
    writeFileSync(join(directory, "README.md"), "hello\n");
    writeFileSync(join(directory, "src", "app.ts"), "export {};\n");
    writeFileSync(join(directory, "node_modules", "ignored.js"), "x\n");

    const result = await listProjectFiles(directory);

    expect(result.vcs).toBeNull();
    expect(result.files.map((file) => file.path)).toEqual(["README.md", "src/app.ts"]);
    expect(result.changed).toBe(0);
    expect(result.truncated).toBe(false);
  });

  test.skipIf(!gitAvailable)("marks modified, added and deleted files", async () => {
    const directory = tempDirectory();
    git(directory, "init", "-q");
    writeFileSync(join(directory, "tracked.txt"), "one\n");
    writeFileSync(join(directory, "removed.txt"), "gone\n");
    writeFileSync(join(directory, "staged-removal.txt"), "bye\n");
    git(directory, "add", "tracked.txt", "removed.txt", "staged-removal.txt");
    git(
      directory,
      "-c",
      "user.email=test@example.com",
      "-c",
      "user.name=OpenCodeBar Test",
      "commit",
      "-q",
      "-m",
      "initial",
    );

    writeFileSync(join(directory, "tracked.txt"), "one\ntwo\n");
    writeFileSync(join(directory, "untracked.txt"), "new\n");
    rmSync(join(directory, "removed.txt"));
    git(directory, "rm", "-q", "staged-removal.txt");

    const result = await listProjectFiles(directory);
    const statuses = Object.fromEntries(
      result.files.map((file) => [file.path, file.status ?? null]),
    );

    expect(result.vcs).toBe("git");
    expect(statuses["tracked.txt"]).toBe("modified");
    expect(statuses["untracked.txt"]).toBe("added");
    expect(statuses["removed.txt"]).toBe("deleted");
    expect(statuses["staged-removal.txt"]).toBe("deleted");
    expect(result.changed).toBe(4);
    expect(result.total).toBe(4);
  });

  test("reports a folder that does not exist", async () => {
    await expect(listProjectFiles("/definitely/not/a/project")).rejects.toThrow(
      "Project folder not found",
    );
  });
});

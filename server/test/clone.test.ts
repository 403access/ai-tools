import { afterEach, describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cloneRepository, normalizeRepositoryURL } from "../src/clone.ts";

const roots: string[] = [];

function tempRoot(): string {
  const root = mkdtempSync(join(tmpdir(), "opencodebar-clone-"));
  roots.push(root);
  return root;
}

function git(cwd: string, args: string[]): void {
  execFileSync("git", args, {
    cwd,
    env: {
      ...process.env,
      GIT_AUTHOR_NAME: "Test",
      GIT_AUTHOR_EMAIL: "test@example.com",
      GIT_COMMITTER_NAME: "Test",
      GIT_COMMITTER_EMAIL: "test@example.com",
    },
  });
}

function makeRepository(directory: string): void {
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, "README.md"), "# Example\n");
  git(directory, ["init", "-q"]);
  git(directory, ["add", "README.md"]);
  git(directory, ["commit", "-q", "-m", "Initial commit"]);
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("repository URLs", () => {
  test("normalizes full URLs, SSH remotes, and GitHub shorthand", () => {
    expect(normalizeRepositoryURL("https://github.com/acme/widgets.git")).toEqual({
      url: "https://github.com/acme/widgets.git",
      name: "widgets",
    });
    expect(normalizeRepositoryURL("acme/widgets")).toEqual({
      url: "https://github.com/acme/widgets",
      name: "widgets",
    });
    expect(normalizeRepositoryURL("acme/widgets/")).toEqual({
      url: "https://github.com/acme/widgets/",
      name: "widgets",
    });
    expect(normalizeRepositoryURL("github.com/acme/widgets")).toEqual({
      url: "https://github.com/acme/widgets",
      name: "widgets",
    });
    expect(normalizeRepositoryURL("git@github.com:acme/widgets.git")).toEqual({
      url: "git@github.com:acme/widgets.git",
      name: "widgets",
    });
    expect(normalizeRepositoryURL("ssh://git@example.com/acme/widgets.git")).toEqual({
      url: "ssh://git@example.com/acme/widgets.git",
      name: "widgets",
    });
    expect(normalizeRepositoryURL("https://example.com/acme/a%20project")).toEqual({
      url: "https://example.com/acme/a%20project",
      name: "a project",
    });
  });

  test("rejects options and unsupported transports", () => {
    for (const value of ["", "   ", "--upload-pack=evil", "ftp://example.com/repo", "acme"]) {
      expect(() => normalizeRepositoryURL(value)).toThrow();
    }
  });
});

describe("cloneRepository", () => {
  test("clones into a parent folder and reports the working tree", async () => {
    const root = tempRoot();
    const source = join(root, "source");
    makeRepository(source);

    const cloned = await cloneRepository({
      url: `file://${source}`,
      parent: root,
      name: "cloned",
    });

    expect(cloned.name).toBe("cloned");
    expect(cloned.directory).toBe(join(realpathSync(root), "cloned"));
    expect(existsSync(join(cloned.directory, "README.md"))).toBe(true);

    await expect(
      cloneRepository({ url: `file://${source}`, parent: root, name: "cloned" }),
    ).rejects.toMatchObject({ status: 409 });
  });

  test("accepts an explicit destination directory", async () => {
    const root = tempRoot();
    const source = join(root, "source");
    makeRepository(source);

    const directory = join(root, "nested", "checkout");
    const cloned = await cloneRepository({ url: `file://${source}`, directory });

    expect(cloned.directory).toBe(join(realpathSync(root), "nested", "checkout"));
    expect(cloned.name).toBe("checkout");
    expect(existsSync(join(directory, "README.md"))).toBe(true);
  });

  test("reports git failures without leaking credentials", async () => {
    const root = tempRoot();
    const url = `https://user:secret@example.invalid/acme/widgets.git`;

    const error = await cloneRepository({ url, parent: root }).catch((caught) => caught);
    expect(error).toMatchObject({ status: 422 });
    expect(error.message).not.toContain("secret");
  });
});

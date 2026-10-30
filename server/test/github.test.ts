import { describe, expect, test } from "bun:test";
import {
  GitHubError,
  groupJobsIntoStages,
  parseGitHubRemote,
  parseWorkflowJobs,
} from "../src/github.ts";
import type { GitHubFlowJob, GitHubFlows } from "../src/types.ts";
import { body, request, setup } from "./helpers/api.ts";

const workflow = `name: Deploy
on: push

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: npm test

  build:
    name: Build
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - run: npm run build

  test:
    needs: [build]
    runs-on: ubuntu-latest

  package:
    needs:
      - test
    runs-on: ubuntu-latest

  # A comment that should not become a job.
  deploy:
    needs:
      - package
    name: Deploy (\${{ matrix.target }})
    strategy:
      matrix:
        target: [staging, production]
`;

function job(id: number, name: string, status: GitHubFlowJob["status"] = "success"): GitHubFlowJob {
  return {
    id,
    name,
    status,
    durationMs: 1_000,
    labels: ["ubuntu-latest"],
    htmlURL: "https://github.com/acme/storefront/actions/runs/1",
    stage: 0,
    steps: [],
  };
}

describe("GitHub remote parsing", () => {
  test("accepts the remote forms git stores", () => {
    for (const remote of [
      "https://github.com/acme/storefront.git",
      "https://github.com/acme/storefront",
      "git@github.com:acme/storefront.git",
      "ssh://git@github.com/acme/storefront.git",
      "github.com/acme/storefront",
    ]) {
      expect(parseGitHubRemote(remote)).toMatchObject({
        owner: "acme",
        repo: "storefront",
        url: "https://github.com/acme/storefront",
      });
    }
  });

  test("rejects remotes for other hosts and malformed paths", () => {
    expect(parseGitHubRemote("https://gitlab.com/acme/storefront.git")).toBeNull();
    expect(parseGitHubRemote("git@github.com:acme")).toBeNull();
    expect(parseGitHubRemote("")).toBeNull();
  });
});

describe("workflow needs", () => {
  test("reads scalar, inline and block needs", () => {
    expect(parseWorkflowJobs(workflow)).toEqual([
      { id: "lint", needs: [] },
      { id: "build", name: "Build", needs: ["lint"] },
      { id: "test", needs: ["build"] },
      { id: "package", needs: ["test"] },
      {
        id: "deploy",
        name: "Deploy (${{ matrix.target }})",
        needs: ["package"],
      },
    ]);
  });

  test("groups jobs into dependency stages", () => {
    const stages = groupJobsIntoStages(
      [
        job(1, "lint"),
        job(2, "Build"),
        job(3, "test", "running"),
        job(4, "Build (18)"),
      ],
      parseWorkflowJobs(workflow),
    );

    expect(stages.map((stage) => stage.name)).toEqual(["Lint", "Build", "Test"]);
    expect(stages.map((stage) => stage.status)).toEqual(["success", "success", "running"]);
    expect(stages[1]?.jobs.map((entry) => entry.name)).toEqual(["Build", "Build (18)"]);
  });
});

describe("project flows endpoint", () => {
  test("returns the injected payload and validates the run id", async () => {
    const payload: GitHubFlows = {
      repository: {
        owner: "acme",
        name: "storefront",
        url: "https://github.com/acme/storefront",
        remote: "git@github.com:acme/storefront.git",
      },
      branch: "main",
      runs: [],
      run: null,
      commit: null,
      generatedAt: 1,
    };
    const calls: Array<{ directory: string; runID?: number; force?: boolean }> = [];
    const { db, handler } = setup({}, {
      github: {
        async flows(directory, options) {
          calls.push({ directory, ...options });
          return payload;
        },
      },
    });
    db.replaceProjects([
      {
        id: "prj_flow",
        canonical: "/tmp/storefront",
        time: { created: 1, updated: 2 },
        sandboxes: [],
      },
    ]);

    const response = await handler(
      request("/api/project/prj_flow/flows?run=4821&refresh=1"),
    );
    expect(response.status).toBe(200);
    const result = await body<{ data: GitHubFlows }>(response);
    expect(result.data.repository.owner).toBe("acme");
    expect(calls).toEqual([
      { directory: "/tmp/storefront", runID: 4821, force: true },
    ]);

    const invalid = await handler(request("/api/project/prj_flow/flows?run=nope"));
    expect(invalid.status).toBe(400);
    expect((await handler(request("/api/project/nope/flows"))).status).toBe(404);
    expect(
      (await handler(request("/api/project/prj_flow/flows", { method: "POST" }))).status,
    ).toBe(405);
    db.close();
  });

  test("surfaces GitHub errors with their status", async () => {
    const { db, handler } = setup({}, {
      github: {
        async flows() {
          throw new GitHubError("GitHub rejected the token", 401);
        },
      },
    });
    db.replaceProjects([
      {
        id: "prj_flow",
        canonical: "/tmp/storefront",
        time: { created: 1, updated: 2 },
        sandboxes: [],
      },
    ]);

    const response = await handler(request("/api/project/prj_flow/flows"));
    expect(response.status).toBe(401);
    const failure = await body<{ error: { message: string } }>(response);
    expect(failure.error.message).toContain("token");
    db.close();
  });
});

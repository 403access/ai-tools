import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { projectDisplayName, projectSearchValues, uniqueProjects } from "../hub.ts";
import {
  describeError,
  failure,
  findProject,
  jsonText,
} from "./common.ts";
import type { ToolContext } from "./common.ts";

const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;
const WRITE = { readOnlyHint: false, openWorldHint: false } as const;

function projectRef(id: string): string {
  return encodeURIComponent(id);
}

export function registerProjectTools(server: McpServer, context: ToolContext): void {
  server.registerTool(
    "list_projects",
    {
      title: "List OpenCode projects",
      description:
        "List the projects OpenCode has run in, including the project id, display name, and checkout path. " +
        "Use this to find the right project before creating a session.",
      inputSchema: {
        query: z
          .string()
          .optional()
          .describe("Optional text to filter projects by name, folder, path, or id."),
        limit: z
          .number()
          .int()
          .min(1)
          .max(200)
          .optional()
          .describe("Maximum projects to return. Defaults to 30."),
      },
      annotations: READ_ONLY,
    },
    async ({ query, limit }) => {
      try {
        const projects = uniqueProjects(await context.client().projects());
        const needle = query?.trim().toLowerCase();
        const filtered = needle
          ? projects.filter((project) =>
              projectSearchValues(project).some((value) =>
                value.toLowerCase().includes(needle),
              ),
            )
          : projects;
        const selected = filtered.slice(0, limit ?? 30);
        return jsonText(
          selected.length
            ? selected.map((project) => ({
                id: project.id,
                name: projectDisplayName(project),
                path: project.canonical,
                vcs: project.vcs ?? null,
                lastActive: new Date(
                  project.time.active ??
                    project.time.updated ??
                    project.time.created ??
                    Date.now(),
                ).toISOString(),
              }))
            : [],
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_project",
    {
      title: "Get a project",
      description: "Read one project's checkout path, sandboxes, VCS type, and timestamps.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
      },
      annotations: READ_ONLY,
    },
    async ({ project }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        return jsonText(await client.get(`/api/project/${projectRef(resolved.project.id)}`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_project_changes",
    {
      title: "Get a project's file changes",
      description:
        "Read the file patches written by the project's recent sessions, grouped by file with added and removed totals.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
        sessions: z
          .number()
          .int()
          .min(1)
          .max(100)
          .optional()
          .describe("How many recent sessions to inspect. Defaults to 10."),
      },
      annotations: READ_ONLY,
    },
    async ({ project, sessions }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        const suffix = sessions ? `?sessions=${sessions}` : "";
        return jsonText(
          await client.get(
            `/api/project/${projectRef(resolved.project.id)}/changes${suffix}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_project_files",
    {
      title: "List a project's files",
      description:
        "List the project folder as it exists on disk, with git working-tree status when the checkout is a repository.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
      },
      annotations: READ_ONLY,
    },
    async ({ project }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        return jsonText(
          await client.get(`/api/project/${projectRef(resolved.project.id)}/files`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_project_git",
    {
      title: "Get a project's repository graph",
      description:
        "Read branches, tags, and the reachable commit graph for a Git project. Returns null when the folder is not a work tree.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
        limit: z
          .number()
          .int()
          .min(1)
          .max(20_000)
          .optional()
          .describe("Maximum commits to return. Defaults to 2,000."),
      },
      annotations: READ_ONLY,
    },
    async ({ project, limit }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        const suffix = limit ? `?limit=${limit}` : "";
        return jsonText(
          await client.get(
            `/api/project/${projectRef(resolved.project.id)}/git${suffix}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_project_flows",
    {
      title: "Get GitHub Actions flows",
      description:
        "Read recent GitHub Actions runs, jobs, checks, and the workflow dependency graph for the project's repository.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
        run: z
          .number()
          .int()
          .positive()
          .optional()
          .describe("Workflow run id to inspect. Omit for the latest run."),
        refresh: z
          .boolean()
          .optional()
          .describe("Bypass the hub's short-lived GitHub cache."),
      },
      annotations: READ_ONLY,
    },
    async ({ project, run, refresh }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        const params = new URLSearchParams();
        if (run) params.set("run", String(run));
        if (refresh) params.set("refresh", "1");
        const suffix = params.size ? `?${params.toString()}` : "";
        return jsonText(
          await client.get(
            `/api/project/${projectRef(resolved.project.id)}/flows${suffix}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_project_scripts",
    {
      title: "List project scripts",
      description:
        "List the high-level scripts a project already declares in package.json, Makefile, Justfile, or Composer manifests.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
      },
      annotations: READ_ONLY,
    },
    async ({ project }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        return jsonText(
          await client.get(`/api/project/${projectRef(resolved.project.id)}/scripts`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "run_project_script",
    {
      title: "Run a project script",
      description:
        "Start one discovered project script in a new terminal on the hub host. The hub re-discovers the script and chooses the executable and arguments.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
        source: z
          .string()
          .describe("Script source from list_project_scripts, for example package.json or Makefile."),
        name: z.string().describe("Script name from list_project_scripts."),
      },
      annotations: WRITE,
    },
    async ({ project, source, name }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        return jsonText(
          await client.post(
            `/api/project/${projectRef(resolved.project.id)}/scripts/run`,
            { source, name },
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_project_documentation",
    {
      title: "Get a project's brief",
      description:
        "Read the editable description, mission, vision, and prompt-derived feature log for a project.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
      },
      annotations: READ_ONLY,
    },
    async ({ project }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        return jsonText(
          await client.get(`/api/project/${projectRef(resolved.project.id)}/docs`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "update_project_documentation",
    {
      title: "Update a project's brief",
      description:
        "Replace one or more editable project brief fields. Only the fields you pass are changed.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
        description: z.string().optional().describe("What the project is."),
        mission: z.string().optional().describe("Why the project exists."),
        vision: z.string().optional().describe("What the project should become."),
      },
      annotations: WRITE,
    },
    async ({ project, description, mission, vision }) => {
      if (description === undefined && mission === undefined && vision === undefined) {
        return failure("Provide description, mission, or vision.");
      }
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        return jsonText(
          await client.patch(`/api/project/${projectRef(resolved.project.id)}/docs`, {
            ...(description !== undefined ? { description } : {}),
            ...(mission !== undefined ? { mission } : {}),
            ...(vision !== undefined ? { vision } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_github_repositories",
    {
      title: "List GitHub repositories",
      description:
        "List repositories visible to the hub's GitHub login. Repositories already cloned on this Mac include `clonedDirectory`.",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: true },
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/github/repos"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "clone_repository",
    {
      title: "Clone a git repository",
      description:
        "Clone a repository onto the hub host. Use the GitHub repository's clone URL, or any git URL.",
      inputSchema: {
        url: z.string().describe("Repository clone URL."),
        parent: z.string().optional().describe("Parent folder to clone into."),
        name: z.string().optional().describe("Folder name for the checkout."),
        directory: z.string().optional().describe("Exact destination directory."),
      },
      annotations: { readOnlyHint: false, openWorldHint: true },
    },
    async ({ url, parent, name, directory }) => {
      try {
        return jsonText(
          await context.client().post("/api/git/clone", {
            url,
            ...(parent ? { parent } : {}),
            ...(name ? { name } : {}),
            ...(directory ? { directory } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "create_worktree",
    {
      title: "Create a git worktree",
      description:
        "Create an isolated checkout from a Git project so a session can work on a branch without disturbing the main checkout.",
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
        from: z.string().optional().describe("Revision or branch to start from."),
        branch: z.string().optional().describe("New branch name."),
        directory: z.string().optional().describe("Destination directory."),
        name: z.string().optional().describe("Friendly worktree name."),
      },
      annotations: WRITE,
    },
    async ({ project, from, branch, directory, name }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);
        return jsonText(
          await client.post("/api/worktree", {
            projectID: resolved.project.id,
            ...(from ? { from } : {}),
            ...(branch ? { branch } : {}),
            ...(directory ? { directory } : {}),
            ...(name ? { name } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );
}
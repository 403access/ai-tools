#!/usr/bin/env bun
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import type { Project, Session } from "../types.ts";
import {
  deriveTitle,
  discoverHub,
  HubClient,
  HubError,
  projectDisplayName,
  projectSearchValues,
  resolveProject,
  uniqueProjects,
} from "./hub.ts";

const INSTRUCTIONS = `OpenCodeBar hub tools for the OpenCode projects and sessions on this Mac.

When the user asks to start new work in a project — for example "create a new session in project X implementing Y" —
call create_session with the project name or path and the full task as the prompt. Use list_projects first when the
project name is uncertain. The tool creates the OpenCode session in the project's checkout and sends the prompt, so
the new task starts immediately and appears in the OpenCodeBar task board.

Use list_sessions, get_session, and send_prompt to follow up on work that was already started.`;

function client(): HubClient {
  return new HubClient(discoverHub());
}

function text(value: string) {
  return { content: [{ type: "text" as const, text: value }] };
}

function failure(value: string) {
  return { content: [{ type: "text" as const, text: value }], isError: true };
}

function describeError(caught: unknown): string {
  if (caught instanceof HubError) return caught.message;
  if (caught instanceof Error) return caught.message;
  return String(caught);
}

function candidateList(projects: Project[]): string {
  return projects
    .map((project) => `- ${projectDisplayName(project)} (${project.canonical})`)
    .join("\n");
}

function projectSummary(project: Project) {
  return {
    id: project.id,
    name: projectDisplayName(project),
    path: project.canonical,
    vcs: project.vcs ?? null,
    lastActive: new Date(
      project.time.active ?? project.time.updated ?? project.time.created ?? Date.now(),
    ).toISOString(),
  };
}

function sessionSummary(session: Session) {
  const project = session.projectID;
  return {
    id: session.id,
    title: session.title?.trim() || "(untitled)",
    project,
    directory: session.location?.directory ?? null,
    parentID: session.parentID ?? null,
    agent: session.agent ?? null,
    model: session.model ? `${session.model.providerID}/${session.model.id}` : null,
    status: session.control?.state ?? session.task?.status ?? null,
    updated: new Date(session.time?.updated ?? Date.now()).toISOString(),
  };
}

function resolveOrExplain(
  projects: Project[],
  query: string,
): { project: Project } | { error: string } {
  const distinct = uniqueProjects(projects);
  const resolution = resolveProject(distinct, query);
  if ("error" in resolution) {
    const known = distinct.slice(0, 15).map((project) => projectDisplayName(project));
    const suffix = known.length
      ? ` Known projects: ${known.join(", ")}.`
      : " The hub has no projects yet.";
    return { error: `${resolution.error}${suffix}` };
  }
  if ("candidates" in resolution) {
    return {
      error:
        `"${query}" matches more than one project:\n${candidateList(resolution.candidates)}\n` +
        `Call the tool again with the absolute path of the intended project.`,
    };
  }
  return { project: resolution.project };
}

export function createServer(getClient: () => HubClient = client): McpServer {
  const server = new McpServer(
    { name: "opencodebar", version: "1.0.0" },
    { instructions: INSTRUCTIONS },
  );

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
    },
    async ({ query, limit }) => {
      try {
        const projects = uniqueProjects(await getClient().projects());
        const needle = query?.trim().toLowerCase();
        const filtered = needle
          ? projects.filter((project) =>
              projectSearchValues(project).some((value) =>
                value.toLowerCase().includes(needle),
              ),
            )
          : projects;
        const selected = filtered.slice(0, limit ?? 30);
        return text(
          selected.length
            ? JSON.stringify(selected.map(projectSummary), null, 2)
            : `No projects match "${query ?? ""}".`,
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "create_session",
    {
      title: "Create a session in a project",
      description:
        "Create a new OpenCode session in a project's checkout and send the initial prompt. " +
        "Use this when the user says to start new work in a project, for example " +
        '"create a new session in project X implementing Y". The project can be a display name, folder name, id, or path.',
      inputSchema: {
        project: z
          .string()
          .describe("Project display name, folder name, project id, or absolute checkout path."),
        prompt: z
          .string()
          .optional()
          .describe("The task to send to the new session. Omit to only create the empty session."),
        title: z
          .string()
          .optional()
          .describe("Optional session title. Defaults to the first line of the prompt."),
      },
    },
    async ({ project, prompt, title }) => {
      try {
        const hub = getClient();
        const projects = await hub.projects();
        const resolved = resolveOrExplain(projects, project ?? "");
        if ("error" in resolved) return failure(resolved.error);

        const target = resolved.project;
        const body = prompt?.trim() ?? "";
        const sessionTitle = title?.trim() || deriveTitle(body);
        const session = await hub.createSession({
          title: sessionTitle,
          directory: target.canonical,
        });

        let prompted = false;
        if (body) {
          try {
            await hub.promptSession(session.id, body);
            prompted = true;
          } catch (caught) {
            return failure(
              `Created session ${session.id} in ${projectDisplayName(target)}, but the prompt could not be sent: ` +
                `${describeError(caught)}. Retry with send_prompt and session "${session.id}".`,
            );
          }
        }

        return text(
          JSON.stringify(
            {
              sessionID: session.id,
              title: session.title?.trim() || sessionTitle || null,
              project: projectSummary(target),
              prompted,
              message: prompted
                ? `Session created in ${projectDisplayName(target)} and the prompt was sent.`
                : `Empty session created in ${projectDisplayName(target)}.`,
            },
            null,
            2,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_sessions",
    {
      title: "List sessions",
      description:
        "List recent OpenCode sessions, optionally filtered to one project or by title text. " +
        "Shows the session id needed by get_session and send_prompt.",
      inputSchema: {
        project: z
          .string()
          .optional()
          .describe("Optional project display name, folder name, id, or path."),
        query: z.string().optional().describe("Optional text to match against session titles."),
        limit: z
          .number()
          .int()
          .min(1)
          .max(200)
          .optional()
          .describe("Maximum sessions to return. Defaults to 20."),
      },
    },
    async ({ project, query, limit }) => {
      try {
        const hub = getClient();
        let projectID: string | undefined;
        const projectQuery = project?.trim();
        if (projectQuery) {
          const resolved = resolveOrExplain(await hub.projects(), projectQuery);
          if ("error" in resolved) return failure(resolved.error);
          projectID = resolved.project.id;
        }

        const sessions = await hub.sessions({ project: projectID, query, limit });
        return text(
          sessions.length
            ? JSON.stringify(sessions.map(sessionSummary), null, 2)
            : "No sessions match.",
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_session",
    {
      title: "Get a session",
      description:
        "Read the current state of one session: title, project, status, control state, cost, and token usage.",
      inputSchema: {
        session: z.string().describe("Session id, for example ses_..."),
      },
    },
    async ({ session }) => {
      try {
        const value = await getClient().session(session.trim());
        return text(JSON.stringify(value, null, 2));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "send_prompt",
    {
      title: "Send a prompt to a session",
      description:
        "Send a follow-up message to an existing session. Running sessions queue the message by default; " +
        "use delivery \"steer\" to interrupt the current turn instead.",
      inputSchema: {
        session: z.string().describe("Session id, for example ses_..."),
        prompt: z.string().describe("The message to send."),
        delivery: z
          .enum(["queue", "steer"])
          .optional()
          .describe("queue waits for the current turn; steer interrupts it. Defaults to the hub's choice."),
      },
    },
    async ({ session, prompt, delivery }) => {
      try {
        const body = prompt.trim();
        if (!body) return failure("The prompt is empty.");
        await getClient().promptSession(session.trim(), body, delivery);
        return text(
          JSON.stringify(
            {
              sessionID: session.trim(),
              delivery: delivery ?? "default",
              message: "Prompt sent.",
            },
            null,
            2,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  return server;
}

if (import.meta.main) {
  const server = createServer();
  await server.connect(new StdioServerTransport());
  console.error("OpenCodeBar MCP server connected over stdio");
}

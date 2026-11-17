import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { ToolContext } from "./common.ts";
import {
  deriveTitle,
  projectDisplayName,
  type HubClient,
} from "../hub.ts";
import {
  describeError,
  failure,
  findProject,
  instant,
  jsonText,
  queryString,
  text,
} from "./common.ts";

const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;
const WRITE = { readOnlyHint: false, openWorldHint: false } as const;

const MODEL_REF = z.object({
  id: z.string().describe("Model id, for example claude-sonnet-4."),
  providerID: z.string().describe("Provider id, for example anthropic."),
  variant: z.string().optional().describe("Optional model variant."),
});

const ATTACHMENTS = z
  .array(z.record(z.string(), z.unknown()))
  .describe("OpenCode prompt file attachments. Each item needs a uri and may carry image metadata.");

const DELIVERY = z
  .enum(["queue", "steer"])
  .optional()
  .describe(
    "queue waits for the current turn; steer interrupts it. Defaults to the hub's choice.",
  );

function sessionPath(id: string): string {
  return `/api/session/${encodeURIComponent(id.trim())}`;
}

function checkAttachments(files: Array<Record<string, unknown>> | undefined): string | null {
  if (!files) return null;
  for (const file of files) {
    if (typeof file.uri !== "string" || !file.uri.trim()) {
      return "Every file attachment needs a string uri.";
    }
  }
  return null;
}

async function projectID(
  client: HubClient,
  project: string | undefined,
): Promise<{ id: string } | { error: string }> {
  if (!project?.trim()) return { id: "" };
  const resolved = await findProject(client, project);
  if ("error" in resolved) return { error: resolved.error };
  return { id: resolved.project.id };
}

export function registerSessionTools(server: McpServer, context: ToolContext): void {
  server.registerTool(
    "create_session",
    {
      title: "Create a session in a project",
      description:
        "Create a new OpenCode session in a project's checkout and send the initial prompt. " +
        "Use this when the user says to start new work in a project, for example " +
        '"create a new session in project X implementing Y". The project can be a display name, folder name, id, or path. ' +
        "Optionally pick the model and agent before the first prompt.",
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
        model: MODEL_REF.optional().describe("Model to use before the first prompt."),
        agent: z.string().optional().describe("OpenCode agent to use for the session."),
      },
      annotations: WRITE,
    },
    async ({ project, prompt, title, model, agent }) => {
      try {
        const client = context.client();
        const resolved = await findProject(client, project);
        if ("error" in resolved) return failure(resolved.error);

        const target = resolved.project;
        const body = prompt?.trim() ?? "";
        const sessionTitle = title?.trim() || deriveTitle(body);
        const session = await client.createSession({
          title: sessionTitle,
          directory: target.canonical,
        });

        if (model || agent) {
          try {
            if (model) await client.post(`${sessionPath(session.id)}/model`, { model });
            if (agent) await client.post(`${sessionPath(session.id)}/agent`, { agent });
          } catch (caught) {
            return failure(
              `Created session ${session.id} in ${projectDisplayName(target)}, but the model/agent could not be selected: ` +
                `${describeError(caught)}. Use set_session_model or set_session_agent and then send_prompt.`,
            );
          }
        }

        let prompted = false;
        if (body) {
          try {
            await client.promptSession(session.id, body);
            prompted = true;
          } catch (caught) {
            return failure(
              `Created session ${session.id} in ${projectDisplayName(target)}, but the prompt could not be sent: ` +
                `${describeError(caught)}. Retry with send_prompt and session "${session.id}".`,
            );
          }
        }

        return jsonText({
          sessionID: session.id,
          title: session.title?.trim() || sessionTitle || null,
          project: {
            id: target.id,
            name: projectDisplayName(target),
            path: target.canonical,
          },
          model: model ? `${model.providerID}/${model.id}` : null,
          agent: agent ?? null,
          prompted,
          message: prompted
            ? `Session created in ${projectDisplayName(target)} and the prompt was sent.`
            : `Empty session created in ${projectDisplayName(target)}.`,
        });
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
        "List recent OpenCode sessions with filters for project, parent session, running state, and title/directory text. " +
        "Returns the session ids needed by get_session and the other session tools.",
      inputSchema: {
        project: z
          .string()
          .optional()
          .describe("Optional project display name, folder name, id, or path."),
        query: z
          .string()
          .optional()
          .describe("Optional text to match against session titles and directories."),
        parent: z.string().optional().describe("Only return child sessions of this session id."),
        active: z.boolean().optional().describe("Only return sessions that are running."),
        order: z
          .enum(["asc", "desc"])
          .optional()
          .describe("Sort by update time. Defaults to desc."),
        limit: z
          .number()
          .int()
          .min(1)
          .max(5_000)
          .optional()
          .describe("Maximum sessions to return. Defaults to 20."),
        offset: z
          .number()
          .int()
          .min(0)
          .optional()
          .describe("Rows to skip for paging. Defaults to 0."),
      },
      annotations: READ_ONLY,
    },
    async ({ project, query, parent, active, order, limit, offset }) => {
      try {
        const client = context.client();
        const projectLookup = await projectID(client, project);
        if ("error" in projectLookup) return failure(projectLookup.error);

        const suffix = queryString({
          project: projectLookup.id,
          parentID: parent,
          active: active ? "true" : undefined,
          order: order ?? "desc",
          q: query,
          limit: limit ?? 20,
          offset,
        });
        const response = await client.get<{ data?: unknown[] }>(`/api/session${suffix}`);
        return jsonText(response?.data ?? []);
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
        "Read one session's current state: title, project, status, control state, cost, tokens, model, and agent.",
      inputSchema: {
        session: z.string().describe("Session id, for example ses_..."),
      },
      annotations: READ_ONLY,
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().session(session.trim()));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_session_messages",
    {
      title: "Read session messages",
      description:
        "Page a session's cached conversation newest first. Pass a cursor from the previous page, or `since` for a delta while a session runs.",
      inputSchema: {
        session: z.string().describe("Session id, for example ses_..."),
        limit: z
          .number()
          .int()
          .min(1)
          .max(500)
          .optional()
          .describe("Maximum messages per page. Defaults to 100."),
        cursor: z.string().optional().describe("Cursor from the previous response."),
        since: z
          .number()
          .optional()
          .describe("Only messages created or updated at/after this epoch-millisecond time."),
      },
      annotations: READ_ONLY,
    },
    async ({ session, limit, cursor, since }) => {
      try {
        const suffix = queryString({ limit: limit ?? 100, cursor, since });
        return jsonText(
          await context.client().get(`${sessionPath(session)}/message${suffix}`),
        );
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
        "Send a follow-up message to an existing session. Running sessions queue the message by default; use delivery " +
        '"steer" to interrupt the current turn. `startAt` or `forMs` delays delivery like a timed queue.',
      inputSchema: {
        session: z.string().describe("Session id, for example ses_..."),
        prompt: z
          .string()
          .optional()
          .describe("The message to send. Omit only when sending a file attachment."),
        delivery: DELIVERY,
        startAt: z
          .union([z.string(), z.number()])
          .optional()
          .describe("ISO time or epoch milliseconds to admit the prompt."),
        forMs: z
          .number()
          .int()
          .positive()
          .optional()
          .describe("Delay delivery by this many milliseconds."),
        files: ATTACHMENTS.optional(),
      },
      annotations: WRITE,
    },
    async ({ session, prompt, delivery, startAt, forMs, files }) => {
      const body = prompt?.trim() ?? "";
      const attachmentError = checkAttachments(files);
      if (attachmentError) return failure(attachmentError);
      if (!body && !files?.length) return failure("The prompt is empty.");

      const start = instant(startAt);
      if (startAt !== undefined && start === undefined) {
        return failure("startAt must be an ISO timestamp or epoch milliseconds.");
      }
      try {
        await context.client().promptSession(session.trim(), body, delivery, {
          ...(start !== undefined ? { startAt: start } : {}),
          ...(forMs !== undefined ? { forMs } : {}),
          ...(files?.length ? { files } : {}),
        });
        return jsonText({
          sessionID: session.trim(),
          delivery: delivery ?? "default",
          queuedFor: start !== undefined ? new Date(start).toISOString() : null,
          attachments: files?.length ?? 0,
          message: "Prompt sent.",
        });
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "queue_prompt",
    {
      title: "Queue a prompt",
      description:
        "Store a prompt on a queued task without starting it yet, optionally with a start time. Start it later with start_queued_prompt.",
      inputSchema: {
        session: z.string().describe("Session id of the queued task."),
        prompt: z.string().describe("The prompt to store."),
        startAt: z
          .union([z.string(), z.number()])
          .optional()
          .describe("ISO time or epoch milliseconds when it may start."),
        forMs: z
          .number()
          .int()
          .positive()
          .optional()
          .describe("Delay the earliest start by this many milliseconds."),
      },
      annotations: WRITE,
    },
    async ({ session, prompt, startAt, forMs }) => {
      const body = prompt.trim();
      if (!body) return failure("The prompt is empty.");
      const start = instant(startAt);
      if (startAt !== undefined && start === undefined) {
        return failure("startAt must be an ISO timestamp or epoch milliseconds.");
      }
      try {
        return jsonText(
          await context.client().post(`${sessionPath(session)}/queue`, {
            prompt: body,
            ...(start !== undefined ? { startAt: start } : {}),
            ...(forMs !== undefined ? { forMs } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "cancel_queued_prompt",
    {
      title: "Cancel a queued prompt",
      description: "Remove the stored prompt from a queued task without starting it.",
      inputSchema: {
        session: z.string().describe("Session id of the queued task."),
      },
      annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: false },
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().delete(`${sessionPath(session)}/queue`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "start_queued_prompt",
    {
      title: "Start a queued task now",
      description: "Start a queued task immediately, overriding its start time and the concurrency limit.",
      inputSchema: {
        session: z.string().describe("Session id of the queued task."),
      },
      annotations: WRITE,
    },
    async ({ session }) => {
      try {
        return jsonText(
          await context.client().post(`${sessionPath(session)}/queue/start`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "pause_session",
    {
      title: "Pause a session",
      description:
        "Interrupt a running session and let the hub continue it automatically at a time within the next 30 days.",
      inputSchema: {
        session: z.string().describe("Session id."),
        until: z
          .union([z.string(), z.number()])
          .optional()
          .describe("ISO time or epoch milliseconds to continue at."),
        forMs: z
          .number()
          .int()
          .positive()
          .optional()
          .describe("Continue this many milliseconds from now."),
        forMinutes: z
          .number()
          .positive()
          .optional()
          .describe("Continue this many minutes from now, for convenience."),
      },
      annotations: WRITE,
    },
    async ({ session, until, forMs, forMinutes }) => {
      let target = instant(until);
      if (until !== undefined && target === undefined) {
        return failure("until must be an ISO timestamp or epoch milliseconds.");
      }
      if (forMs !== undefined) target = Date.now() + forMs;
      if (forMinutes !== undefined) target = Date.now() + Math.round(forMinutes * 60_000);
      if (target === undefined) return failure("Provide until, forMs, or forMinutes.");
      try {
        return jsonText(
          await context.client().post(`${sessionPath(session)}/pause`, { until: target }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "stop_session",
    {
      title: "Stop a session",
      description:
        "Interrupt a running session and hold it until continue_session is called.",
      inputSchema: {
        session: z.string().describe("Session id."),
      },
      annotations: WRITE,
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().post(`${sessionPath(session)}/stop`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "continue_session",
    {
      title: "Continue a paused or stopped session",
      description:
        "Clear a pause or stop and send `continue` into the conversation to start a fresh turn.",
      inputSchema: {
        session: z.string().describe("Session id."),
      },
      annotations: WRITE,
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().post(`${sessionPath(session)}/continue`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "fork_session",
    {
      title: "Fork a session",
      description:
        "Copy a session's projected history into a new child session. Pass `before` to copy only messages before that message id.",
      inputSchema: {
        session: z.string().describe("Source session id."),
        before: z.string().optional().describe("Message id to fork before."),
      },
      annotations: WRITE,
    },
    async ({ session, before }) => {
      try {
        return jsonText(
          await context.client().post(`${sessionPath(session)}/fork`, {
            ...(before ? { before } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "set_session_model",
    {
      title: "Switch a session's model",
      description: "Change the model used by subsequent turns in one session.",
      inputSchema: {
        session: z.string().describe("Session id."),
        model: MODEL_REF,
      },
      annotations: WRITE,
    },
    async ({ session, model }) => {
      try {
        await context.client().post(`${sessionPath(session)}/model`, { model });
        return text(`Session ${session.trim()} will use ${model.providerID}/${model.id}.`);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "set_session_agent",
    {
      title: "Switch a session's agent",
      description: "Change the OpenCode agent used by subsequent turns in one session.",
      inputSchema: {
        session: z.string().describe("Session id."),
        agent: z.string().describe("Agent name from list_agents."),
      },
      annotations: WRITE,
    },
    async ({ session, agent }) => {
      try {
        await context.client().post(`${sessionPath(session)}/agent`, { agent });
        return text(`Session ${session.trim()} will use the ${agent} agent.`);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_child_sessions",
    {
      title: "List subagent sessions",
      description:
        "List the child sessions a session started, with their own status and usage.",
      inputSchema: {
        session: z.string().describe("Parent session id."),
      },
      annotations: READ_ONLY,
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().get(`${sessionPath(session)}/children`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_session_forks",
    {
      title: "List session forks",
      description: "List the sessions forked from this conversation and where each fork was cut.",
      inputSchema: {
        session: z.string().describe("Source session id."),
      },
      annotations: READ_ONLY,
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().get(`${sessionPath(session)}/forks`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_session_changes",
    {
      title: "Get session file changes",
      description:
        "Read every file patch a session produced, with additions, deletions, and the diff.",
      inputSchema: {
        session: z.string().describe("Session id."),
      },
      annotations: READ_ONLY,
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().get(`${sessionPath(session)}/changes`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_session_git",
    {
      title: "Get session repository state",
      description:
        "Read the session's repository summary and the commits whose time falls inside the session window.",
      inputSchema: {
        session: z.string().describe("Session id."),
        limit: z
          .number()
          .int()
          .min(1)
          .max(20_000)
          .optional()
          .describe("Maximum commits. Defaults to 2,000."),
      },
      annotations: READ_ONLY,
    },
    async ({ session, limit }) => {
      try {
        return jsonText(
          await context.client().get(
            `${sessionPath(session)}/git${queryString({ limit })}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_session_stats",
    {
      title: "Get session statistics",
      description:
        "Read prompts, steps, tool reliability, recent failures, file impact, and token mix for one session. " +
        "The response says whether the whole history was available.",
      inputSchema: {
        session: z.string().describe("Session id."),
      },
      annotations: READ_ONLY,
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().get(`${sessionPath(session)}/stats`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_pending_prompts",
    {
      title: "List pending prompts",
      description:
        "List prompts the hub admitted but the model has not consumed yet, oldest first.",
      inputSchema: {
        session: z.string().describe("Session id."),
      },
      annotations: READ_ONLY,
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().get(`${sessionPath(session)}/pending`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "cancel_pending_prompt",
    {
      title: "Withdraw a pending prompt",
      description:
        "Remove one queued prompt that the running turn has not consumed. Find its id with list_pending_prompts.",
      inputSchema: {
        session: z.string().describe("Session id."),
        pending: z.string().describe("Pending prompt id."),
      },
      annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: false },
    },
    async ({ session, pending }) => {
      try {
        await context.client().delete(
          `${sessionPath(session)}/pending/${encodeURIComponent(pending.trim())}`,
        );
        return text(`Withdrew pending prompt ${pending.trim()}.`);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_session_forms",
    {
      title: "List waiting forms",
      description:
        "List questions or forms a session is waiting on, including their fields and options.",
      inputSchema: {
        session: z.string().describe("Session id."),
      },
      annotations: READ_ONLY,
    },
    async ({ session }) => {
      try {
        return jsonText(await context.client().get(`${sessionPath(session)}/form`));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "reply_session_form",
    {
      title: "Answer a session form",
      description:
        "Answer a waiting form. The answer object maps field ids to strings, numbers, booleans, or string arrays.",
      inputSchema: {
        session: z.string().describe("Session id."),
        form: z.string().describe("Form id from list_session_forms."),
        answer: z
          .record(
            z.string(),
            z.union([
              z.string(),
              z.number(),
              z.boolean(),
              z.array(z.string()),
            ]),
          )
          .describe("Field id to answer."),
      },
      annotations: WRITE,
    },
    async ({ session, form, answer }) => {
      try {
        await context.client().post(
          `${sessionPath(session)}/form/${encodeURIComponent(form.trim())}/reply`,
          { answer },
        );
        return text(`Answered form ${form.trim()}.`);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "cancel_session_form",
    {
      title: "Cancel a session form",
      description: "Dismiss a waiting form, optionally with a message for the asker.",
      inputSchema: {
        session: z.string().describe("Session id."),
        form: z.string().describe("Form id from list_session_forms."),
        message: z.string().optional().describe("Why the form was dismissed."),
      },
      annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: false },
    },
    async ({ session, form, message }) => {
      try {
        await context.client().delete(
          `${sessionPath(session)}/form/${encodeURIComponent(form.trim())}${queryString({ message })}`,
        );
        return text(`Cancelled form ${form.trim()}.`);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_models",
    {
      title: "List available models",
      description:
        "List the models OpenCode exposes for a directory, as shown in the model picker.",
      inputSchema: {
        directory: z.string().optional().describe("Directory whose provider config should be used."),
      },
      annotations: { readOnlyHint: true, openWorldHint: true },
    },
    async ({ directory }) => {
      try {
        return jsonText(
          await context.client().get(`/api/model${queryString({ directory })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_default_model",
    {
      title: "Get the default model",
      description:
        "Read the model OpenCode uses for a directory when a session has no explicit selection.",
      inputSchema: {
        directory: z.string().optional().describe("Directory whose provider config should be used."),
      },
      annotations: { readOnlyHint: true, openWorldHint: true },
    },
    async ({ directory }) => {
      try {
        return jsonText(
          await context.client().get(`/api/model/default${queryString({ directory })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_agents",
    {
      title: "List agents",
      description: "List the OpenCode agents registered for a directory.",
      inputSchema: {
        directory: z.string().optional().describe("Directory whose agent config should be used."),
      },
      annotations: { readOnlyHint: true, openWorldHint: true },
    },
    async ({ directory }) => {
      try {
        return jsonText(
          await context.client().get(`/api/agent${queryString({ directory })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_tasks",
    {
      title: "List task-board tasks",
      description:
        "List top-level sessions as task cards with their derived status, labels, queue state, and project.",
      inputSchema: {
        project: z
          .string()
          .optional()
          .describe("Optional project display name, folder name, id, or path."),
        limit: z
          .number()
          .int()
          .min(1)
          .max(5_000)
          .optional()
          .describe("Maximum tasks to return. Defaults to 500."),
      },
      annotations: READ_ONLY,
    },
    async ({ project, limit }) => {
      try {
        const client = context.client();
        const projectLookup = await projectID(client, project);
        if ("error" in projectLookup) return failure(projectLookup.error);
        return jsonText(
          await client.get(
            `/api/task${queryString({ project: projectLookup.id, limit: limit ?? 500 })}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "update_task",
    {
      title: "Resolve a task",
      description:
        "Mark a task done, reopen it, or dismiss it. Sending another prompt into the session also reopens it.",
      inputSchema: {
        session: z.string().describe("Session id of the task."),
        status: z
          .enum(["open", "done", "dismissed"])
          .describe("open reopens the task, done moves it out of review, dismissed hides it."),
      },
      annotations: WRITE,
    },
    async ({ session, status }) => {
      try {
        return jsonText(
          await context.client().patch(`/api/task/${encodeURIComponent(session.trim())}`, {
            status,
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );
}
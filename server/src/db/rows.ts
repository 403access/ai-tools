import { ZERO_TOKENS, type Project, type Session, type SessionMessage, type TokenUsage } from "../types.ts";
import { buildSessionTask } from "./taskLabels.ts";

export type Row = Record<string, unknown>;

export function text(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

export function number(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

export function optionalNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

export function median(values: number[]): number | undefined {
  if (!values.length) return undefined;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  const value = sorted.length % 2 === 0 ? (sorted[middle - 1]! + sorted[middle]!) / 2 : sorted[middle]!;
  return Number.isFinite(value) ? Math.round(value * 10) / 10 : undefined;
}

export function parseTokens(raw: unknown): TokenUsage {
  if (typeof raw !== "string" || !raw) return { ...ZERO_TOKENS, cache: { ...ZERO_TOKENS.cache } };
  try {
    const value = JSON.parse(raw) as Partial<TokenUsage> & { cache?: Partial<TokenUsage["cache"]> };
    return {
      input: number(value.input),
      output: number(value.output),
      reasoning: number(value.reasoning),
      cache: {
        read: number(value.cache?.read),
        write: number(value.cache?.write),
      },
    };
  } catch {
    return { ...ZERO_TOKENS, cache: { ...ZERO_TOKENS.cache } };
  }
}

export function rowToSession(row: Row): Session {
  const session: Session = {
    id: String(row.id),
    projectID: String(row.project_id ?? ""),
    cost: number(row.cost),
    tokens: parseTokens(row.tokens),
    time: {
      created: number(row.created),
      updated: number(row.updated),
    },
    location: {},
  };
  const parentID = text(row.parent_id);
  if (parentID) session.parentID = parentID;
  const agent = text(row.agent);
  if (agent) session.agent = agent;
  if (typeof row.model === "string" && row.model) {
    try {
      session.model = JSON.parse(row.model);
    } catch {
      // Ignore a malformed cached model.
    }
  }
  const outcome = text(row.outcome);
  if (outcome) session.outcome = outcome;
  const idle = optionalNumber(row.idle);
  if (idle !== undefined) session.time.idle = idle;
  const viewed = optionalNumber(row.viewed);
  if (viewed !== undefined) session.time.viewed = viewed;
  const archived = optionalNumber(row.archived);
  if (archived !== undefined) session.time.archived = archived;
  const title = text(row.title);
  if (title) session.title = title;
  const subpath = text(row.subpath);
  if (subpath) session.subpath = subpath;
  const directory = text(row.directory);
  if (directory) session.location.directory = directory;
  const forkSessionID = text(row.fork_session_id);
  if (forkSessionID) {
    const fork: NonNullable<Session["fork"]> = { sessionID: forkSessionID };
    if (typeof row.fork_boundary === "string" && row.fork_boundary) {
      try {
        const boundary = JSON.parse(row.fork_boundary);
        if (boundary && typeof boundary === "object") fork.boundary = boundary;
      } catch {
        // Ignore a malformed cached fork boundary.
      }
    }
    session.fork = fork;
  }
  const taskCreated = optionalNumber(row.task_created);
  if (taskCreated !== undefined) {
    session.task = buildSessionTask({
      active: number(row.active) === 1,
      stored: text(row.task_status),
      doneAt: optionalNumber(row.task_done_at),
      createdAt: taskCreated,
      updated: number(row.updated),
      title,
      context: text(row.task_context),
    });
  }
  return session;
}

export function rowToProject(row: Row): Project {
  const project: Project = {
    id: String(row.id),
    canonical: String(row.canonical ?? ""),
    time: {
      created: number(row.created),
      updated: number(row.updated),
    },
    sandboxes: [],
  };
  const vcs = text(row.vcs);
  if (vcs) project.vcs = vcs;
  const name = text(row.name);
  if (name) project.name = name;
  const active = optionalNumber(row.active);
  if (active !== undefined) project.time.active = active;
  if (typeof row.sandboxes === "string" && row.sandboxes) {
    try {
      const parsed = JSON.parse(row.sandboxes);
      if (Array.isArray(parsed)) project.sandboxes = parsed.filter((v): v is string => typeof v === "string");
    } catch {
      // Ignore malformed sandbox data.
    }
  }
  return project;
}

export function rowToMessage(row: Row): SessionMessage {
  const message: SessionMessage = {
    id: String(row.id),
    type: String(row.type ?? "assistant"),
    time: { created: number(row.created) },
  };
  const streamed = optionalNumber(row.streamed);
  if (streamed !== undefined) message.time.streamed = streamed;
  const completed = optionalNumber(row.completed);
  if (completed !== undefined) message.time.completed = completed;
  const body = text(row.text);
  if (body !== undefined) message.text = body;
  if (typeof row.content === "string" && row.content) {
    try {
      message.content = JSON.parse(row.content);
    } catch {
      // Ignore malformed cached content.
    }
  }
  if (typeof row.model === "string" && row.model) {
    try {
      message.model = JSON.parse(row.model);
    } catch {
      // Ignore malformed cached model.
    }
  }
  const agent = text(row.agent);
  if (agent) message.agent = agent;
  const cost = optionalNumber(row.cost);
  if (cost !== undefined) message.cost = cost;
  if (typeof row.tokens === "string" && row.tokens) {
    message.tokens = parseTokens(row.tokens);
  }
  const outcome = text(row.outcome);
  if (outcome) message.outcome = outcome;
  const finish = text(row.finish);
  if (finish) message.finish = finish;
  if (typeof row.error === "string" && row.error) {
    try {
      message.error = JSON.parse(row.error);
    } catch {
      // Ignore malformed cached failure details.
    }
  }
  if (typeof row.retry === "string" && row.retry) {
    try {
      message.retry = JSON.parse(row.retry);
    } catch {
      // Ignore malformed cached retry details.
    }
  }
  return message;
}

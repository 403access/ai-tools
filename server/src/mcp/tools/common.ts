import type { Project } from "../../types.ts";
import {
  HubError,
  projectDisplayName,
  resolveProject,
  uniqueProjects,
  type HubClient,
} from "../hub.ts";

/** What every tool module receives. `client` is lazy so startup does not need a hub. */
export interface ToolContext {
  client(): HubClient;
}

export function text(value: string) {
  return { content: [{ type: "text" as const, text: value }] };
}

export function jsonText(value: unknown) {
  return text(JSON.stringify(value, null, 2));
}

export function failure(value: string) {
  return { content: [{ type: "text" as const, text: value }], isError: true };
}

export function describeError(caught: unknown): string {
  if (caught instanceof HubError) return caught.message;
  if (caught instanceof Error) return caught.message;
  return String(caught);
}

export function candidateList(projects: Project[]): string {
  return projects
    .map((project) => `- ${projectDisplayName(project)} (${project.canonical})`)
    .join("\n");
}

export type ProjectLookup = { project: Project } | { error: string };

export function resolveOrExplain(projects: Project[], query: string): ProjectLookup {
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

/** Resolves a free-form project name/path to the hub row a tool should call. */
export async function findProject(
  client: HubClient,
  query: string,
): Promise<ProjectLookup> {
  return resolveOrExplain(await client.projects(), query);
}

/** Normalizes an ISO timestamp or epoch-millisecond number for API bodies. */
export function instant(value: string | number | undefined): number | undefined {
  if (value === undefined) return undefined;
  if (typeof value === "number") return Number.isFinite(value) ? value : undefined;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

/** Query string from defined values, skipping empty strings and undefined. */
export function queryString(
  values: Record<string, string | number | boolean | undefined>,
): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(values)) {
    if (value === undefined || value === "") continue;
    params.set(key, String(value));
  }
  const encoded = params.toString();
  return encoded ? `?${encoded}` : "";
}
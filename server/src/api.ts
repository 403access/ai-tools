import {
  clampEventThrottle,
  HUB_VERSION,
  lanAddresses,
  type HubConfig,
} from "./config.ts";
import type { HubDB } from "./db.ts";
import { listProjectFiles, ProjectFilesError } from "./files.ts";
import type { Hub } from "./hub.ts";
import { OpenCodeError } from "./opencode.ts";
import type { ServerInfo } from "./types.ts";
import { eventStream } from "./api/event-stream.ts";
import {
  CORS_HEADERS,
  activeResponse,
  deviceFromRequest,
  error,
  intParam,
  isAuthorized,
  json,
  readJSONBody,
  settingsPayload,
} from "./api/support.ts";

export interface ApiDeps {
  db: HubDB;
  hub: Hub;
  config: HubConfig;
  /** Restarts the hub process, exposed to the settings screen. */
  restart?: () => void;
  /** Persists settings changed over the API, so they survive a restart. */
  persistSettings?: (config: HubConfig) => void;
}

export function createHandler(deps: ApiDeps): (request: Request) => Promise<Response> {
  const { db, hub, config, restart, persistSettings } = deps;

  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const pathname = url.pathname.replace(/\/+$/, "") || "/";
    const parts = pathname.split("/").filter(Boolean);

    try {
      // Unauthenticated liveness probe. Used by the clients to check that a
      // pasted URL points at a hub before sending the token.
      if (pathname === "/api/ping") {
        return json({ ok: true, hub: true, version: HUB_VERSION });
      }

      if (!isAuthorized(request, config.token)) {
        return json({ error: { message: "Unauthorized", code: "unauthorized" } }, 401);
      }

      // Every authenticated client identifies itself so the settings screen can
      // show the Mac and iOS/iPadOS apps connected to this hub.
      const device = deviceFromRequest(request);
      if (device) hub.trackDevice(device);

      if (pathname === "/api/devices" && request.method === "GET") {
        return json({ data: hub.devices() });
      }

      if (pathname === "/api/settings") {
        if (request.method === "GET") {
          return json({ data: settingsPayload(config) });
        }
        if (request.method === "PATCH") {
          const body = await readJSONBody(request);
          if (!body) return error("Expected a JSON body", 400);

          const value = body.eventThrottleMs;
          if (typeof value !== "number" || !Number.isFinite(value)) {
            return error("eventThrottleMs must be a number", 400);
          }

          // The hub clamps out-of-range values, so older clients that send a
          // too-small interval still get a usable setting instead of an error.
          hub.setEventThrottle(clampEventThrottle(value));
          persistSettings?.(config);
          return json({ data: settingsPayload(config) });
        }
        return error("Method not allowed", 405);
      }

      if (pathname === "/api/health" || pathname === "/api/hub/info") {
        const health = hub.health();
        return json({
          ok: true,
          version: HUB_VERSION,
          hub: health,
          opencode: health.opencode,
        });
      }

      if (pathname === "/api/info") {
        const health = hub.health();
        const info: ServerInfo = {
          version: hub.state.version ?? `hub-${HUB_VERSION}`,
          pid: process.pid,
          urls: [
            `http://127.0.0.1:${config.port}`,
            ...lanAddresses(config.port).map((entry) => entry.url),
          ],
          capabilities: { persistentPty: false },
          hub: health,
        };
        return json(info);
      }

      if (pathname === "/api/project" && request.method === "GET") {
        return json(db.getProjects());
      }

      if (parts[0] === "api" && parts[1] === "project" && parts.length === 3) {
        const project = db.getProject(decodeURIComponent(parts[2]!));
        return project ? json(project) : error("Project not found", 404);
      }

      if (parts[0] === "api" && parts[1] === "project" && parts[3] === "changes" && parts.length === 4) {
        const id = decodeURIComponent(parts[2]!);
        const sessions = intParam(url.searchParams.get("sessions"), 10, 1, 100);
        return json({ data: await hub.projectChanges(id, sessions) });
      }

      if (parts[0] === "api" && parts[1] === "project" && parts[3] === "files" && parts.length === 4) {
        if (request.method !== "GET") return error("Method not allowed", 405);
        const id = decodeURIComponent(parts[2]!);
        const project = db.getProject(id);
        if (!project) return error("Project not found", 404);
        try {
          return json({ data: await listProjectFiles(project.canonical) });
        } catch (caught) {
          if (caught instanceof ProjectFilesError) return error(caught.message, caught.status);
          throw caught;
        }
      }

      if (pathname === "/api/session" && request.method === "GET") {
        const data = db.getSessions({
          limit: intParam(url.searchParams.get("limit"), 60, 1, 5_000),
          offset: intParam(url.searchParams.get("offset"), 0, 0, 1_000_000),
          project: url.searchParams.get("project") ?? undefined,
          parentID: url.searchParams.get("parentID") ?? undefined,
          active: url.searchParams.get("active") === "true",
          order: url.searchParams.get("order") === "asc" ? "asc" : "desc",
          q: url.searchParams.get("q") ?? undefined,
        });
        return json({ data });
      }

      if (pathname === "/api/session" && request.method === "POST") {
        const body = await readJSONBody(request);
        if (!body) return error("Expected a JSON body", 400);

        const location = body.location;
        const directory =
          location && typeof location === "object"
            ? (location as Record<string, unknown>).directory
            : undefined;
        if (typeof directory !== "string" || !directory.trim()) {
          return error("A location.directory is required", 400);
        }

        const title = typeof body.title === "string" ? body.title.trim() : "";
        const session = await hub.createSession({
          title: title || undefined,
          directory: directory.trim(),
        });
        return json({ data: session });
      }

      if (pathname === "/api/session/active" && request.method === "GET") {
        return json(activeResponse(db));
      }

      if (parts[0] === "api" && parts[1] === "session" && parts.length >= 3) {
        const id = decodeURIComponent(parts[2]!);

        if (parts.length === 4 && parts[3] === "message") {
          const limit = intParam(url.searchParams.get("limit"), 100, 1, 500);
          const cursor = url.searchParams.get("cursor");
          const sinceParam = url.searchParams.get("since");
          const since = sinceParam === null ? undefined : Number.parseFloat(sinceParam);
          const page = await hub.messages(
            id,
            limit,
            cursor,
            since !== undefined && Number.isFinite(since) ? since : undefined,
          );
          return json(page);
        }

        if (parts.length === 4 && parts[3] === "children") {
          return json({ data: await hub.children(id) });
        }

        if (parts.length === 4 && parts[3] === "changes") {
          return json({ data: await hub.changes(id) });
        }

        if (parts.length === 4 && parts[3] === "stats") {
          const stats = await hub.sessionStats(id);
          return stats ? json({ data: stats }) : error("Session not found", 404);
        }

        if (parts.length === 4 && parts[3] === "prompt") {
          if (request.method !== "POST") return error("Method not allowed", 405);

          const body = await readJSONBody(request);
          if (!body) return error("Expected a JSON body", 400);

          const text = typeof body.text === "string" ? body.text.trim() : "";
          if (!text) return error("Prompt text is required", 400);

          let delivery: "steer" | "queue" | undefined;
          if (body.delivery !== undefined && body.delivery !== null) {
            if (body.delivery !== "steer" && body.delivery !== "queue") {
              return error("delivery must be steer or queue", 400);
            }
            delivery = body.delivery;
          }

          return json(await hub.promptSession(id, text, delivery));
        }

        if (parts.length === 4 && parts[3] === "pending") {
          if (request.method !== "GET") return error("Method not allowed", 405);
          return json({ data: await hub.pendingInputs(id) });
        }

        if (parts.length === 5 && parts[3] === "pending") {
          if (request.method !== "DELETE") return error("Method not allowed", 405);
          await hub.cancelPendingInput(id, decodeURIComponent(parts[4]!));
          return new Response(null, { status: 204, headers: CORS_HEADERS });
        }

        if (parts.length === 3) {
          if (request.method !== "GET") return error("Method not allowed", 405);
          const session = await hub.session(id);
          return session ? json({ data: session }) : error("Session not found", 404);
        }
      }

      if (pathname === "/api/experimental/session/stats" && request.method === "GET") {
        const project = url.searchParams.get("project") ?? undefined;
        const stats = await hub.stats(project);
        if (!stats) {
          return error("Statistics are not available yet", 503);
        }
        return json(stats);
      }

      if (pathname === "/api/usage" && request.method === "GET") {
        return json(await hub.ensureUsage(false, false));
      }

      if (pathname === "/api/event" && request.method === "GET") {
        return eventStream(hub, request, device?.id);
      }

      if (pathname === "/api/sync" && request.method === "GET") {
        const raw = url.searchParams.get("since");
        const parsed = raw === null ? undefined : Number.parseInt(raw, 10);
        const since = parsed !== undefined && Number.isFinite(parsed) ? parsed : undefined;
        return json(db.getSync(since));
      }

      if (pathname === "/api/sync" && request.method === "POST") {
        await hub.syncNow();
        return json({ ok: true, hub: hub.health() });
      }

      if (pathname === "/api/server/restart" && request.method === "POST") {
        if (!restart) return error("Restarting is not supported by this hub", 501);
        // Let the response reach the client before the process is replaced.
        setTimeout(restart, 200);
        return json({ ok: true, restarting: true });
      }

      if (pathname === "/api/search" && request.method === "GET") {
        const q = url.searchParams.get("q") ?? "";
        const data = db.getSessions({
          q,
          limit: intParam(url.searchParams.get("limit"), 50, 1, 500),
        });
        return json({ data });
      }

      return error(`No route for ${request.method} ${pathname}`, 404);
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : String(caught);
      console.error(`[hub] ${request.method} ${pathname} failed: ${message}`);
      if (caught instanceof OpenCodeError) {
        return error(message, caught.status ?? 502);
      }
      return error(message, 500);
    }
  };
}

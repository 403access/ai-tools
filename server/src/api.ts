import {
  clampEventThrottle,
  HUB_VERSION,
  lanAddresses,
  type HubConfig,
} from "./config.ts";
import type { HubDB } from "./db.ts";
import { listProjectFiles, ProjectFilesError } from "./files.ts";
import { readProjectGit, readSessionGit } from "./git.ts";
import {
  FileBrowserError,
  listDirectory,
  readFileContent,
  readRawFile,
} from "./browser.ts";
import type { Hub } from "./hub.ts";
import { OpenCodeError } from "./opencode.ts";
import { resolveProjectIcon } from "./projectIcon.ts";
import { resolveAppIcon } from "./system/appIcons.ts";
import type {
  MediaControlResult,
  ServerInfo,
  SystemAppDetail,
  SystemInfo,
  TerminalUpdateInput,
} from "./types.ts";
import { AppActionError, MediaControlError, SystemInfoService } from "./system.ts";
import { TerminalService, type TerminalStore } from "./terminals.ts";
import { TerminalSockets } from "./api/terminal-socket.ts";
import { RemoteSockets } from "./api/remote-socket.ts";
import { VMSockets } from "./api/vm-socket.ts";
import type { HubSocketData } from "./api/socket.ts";
import { VirtualMachineService } from "./vms/service.ts";
import { VMHelperError } from "./vms/helper.ts";
import { VMValidationError, previewConfiguration, previewDraftConfiguration } from "./vms/nixos.ts";
import { catalogForClient } from "./vms/catalog/index.ts";
import type {
  VMAction,
  VMLogType,
  VirtualMachineStore,
} from "./vms/types.ts";
import {
  HostTerminalError,
  HostTerminalService,
  type HostTerminalStore,
} from "./host-terminals.ts";
import { eventStream } from "./api/event-stream.ts";
import { docsResponse, openApiResponse } from "./api/docs.ts";
import {
  emptyRemoteStatus,
  type RemoteConfigureInput,
  type RemoteHost,
} from "./remote.ts";
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
  /** Injectable system collector, used by tests to avoid touching the host. */
  system?: {
    snapshot(force?: boolean): Promise<SystemInfo>;
    control?(action: string, value?: number): Promise<MediaControlResult>;
    appDetail?(path: string): Promise<SystemAppDetail | null>;
    appAction?(path: string, action: string, target?: string): Promise<SystemAppDetail>;
  };
  /** Injectable PTY store, used by tests to avoid a live OpenCode service. */
  terminals?: TerminalStore;
  /** Websocket proxy for terminal streams; the hub wires this into Bun.serve. */
  terminalSockets?: TerminalSockets;
  /** Injectable Terminal.app integration, used by tests to avoid macOS automation. */
  hostTerminals?: HostTerminalStore;
  /** Screen capture and input service used by the Remote tab. */
  remote?: RemoteHost;
  /** Websocket relay for remote-desktop frames and input. */
  remoteSockets?: RemoteSockets;
  /** Virtual-machine definitions and lifecycle, injectable for tests. */
  vms?: VirtualMachineStore;
  /** Websocket relay for VM serial consoles. */
  vmSockets?: VMSockets;
}

export function createHandler(
  deps: ApiDeps,
): (request: Request, server?: Bun.Server<HubSocketData>) => Promise<Response> {
  const { db, hub, config, restart, persistSettings, remote } = deps;
  const system: NonNullable<ApiDeps["system"]> = deps.system ?? new SystemInfoService({
    hub: () => ({
      startedAt: hub.startedAt,
      port: config.port,
      dbPath: config.dbPath,
    }),
  });
  const terminalService = deps.terminals ? null : new TerminalService(hub, db);
  const terminalStore = deps.terminals ?? terminalService!;
  const terminalSockets =
    deps.terminalSockets ?? (terminalService ? new TerminalSockets(terminalService) : undefined);
  const hostTerminals = deps.hostTerminals ?? new HostTerminalService();
  const vms = deps.vms ?? new VirtualMachineService();
  const vmSockets = deps.vmSockets;

  const withVMErrors = async (work: () => Promise<Response>): Promise<Response> => {
    try {
      return await work();
    } catch (caught) {
      if (caught instanceof VMValidationError) return error(caught.message, caught.status);
      if (caught instanceof VMHelperError) return error(caught.message, caught.status);
      throw caught;
    }
  };

  return async (
    request: Request,
    server?: Bun.Server<HubSocketData>,
  ): Promise<Response> => {
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

      // API documentation stays public: the reference is also published on the
      // docs site, and Swagger UI's Authorize button supplies the token for
      // every "Try it out" request. No cached data is exposed here.
      if (pathname === "/api/docs" || pathname === "/api/openapi.json") {
        if (request.method !== "GET") return error("Method not allowed", 405);
        return pathname === "/api/docs" ? docsResponse() : openApiResponse();
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
          return json({ data: settingsPayload(config, hub.preventSleepSupported) });
        }
        if (request.method === "PATCH") {
          const body = await readJSONBody(request);
          if (!body) return error("Expected a JSON body", 400);

          const hasThrottle = body.eventThrottleMs !== undefined;
          const hasSleep = body.preventSleep !== undefined;
          if (!hasThrottle && !hasSleep) {
            return error("Provide eventThrottleMs or preventSleep", 400);
          }

          if (hasThrottle) {
            const value = body.eventThrottleMs;
            if (typeof value !== "number" || !Number.isFinite(value)) {
              return error("eventThrottleMs must be a number", 400);
            }
            // The hub clamps out-of-range values, so older clients that send a
            // too-small interval still get a usable setting instead of an error.
            hub.setEventThrottle(clampEventThrottle(value));
          }

          if (hasSleep) {
            const value = body.preventSleep;
            if (typeof value !== "boolean") {
              return error("preventSleep must be a boolean", 400);
            }
            hub.setPreventSleep(value);
          }

          persistSettings?.(config);
          return json({ data: settingsPayload(config, hub.preventSleepSupported) });
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

      if (pathname === "/api/system" && request.method === "GET") {
        // The collector caches its expensive sections; `refresh=1` is for the
        // system tab's manual refresh and bypasses both caches.
        return json({ data: await system.snapshot(url.searchParams.get("refresh") === "1") });
      }

      if (
        parts[0] === "api" && parts[1] === "system" && parts[2] === "apps" &&
        parts[3] === "icon" && parts.length === 4
      ) {
        if (request.method !== "GET") return error("Method not allowed", 405);

        const appPath = url.searchParams.get("path")?.trim();
        if (!appPath) return error("An application path is required", 400);

        // Only serve artwork for apps the collector actually enumerated, so
        // the endpoint cannot be used to probe arbitrary files on the host.
        const snapshot = await system.snapshot(false);
        const app = snapshot.apps.find((entry) => entry.path === appPath);
        if (!app) return error("Unknown application", 404);

        const icon = await resolveAppIcon(app.path);
        if (!icon) return error("No icon for this application", 404);

        const etag = `"${icon.etag}"`;
        if (request.headers.get("if-none-match") === etag) {
          return new Response(null, {
            status: 304,
            headers: {
              ETag: etag,
              "Cache-Control": "public, max-age=3600",
              ...CORS_HEADERS,
            },
          });
        }

        return new Response(icon.bytes, {
          headers: {
            "Content-Type": icon.contentType,
            "Cache-Control": "public, max-age=3600",
            ETag: etag,
            ...CORS_HEADERS,
          },
        });
      }

      if (
        parts[0] === "api" && parts[1] === "system" && parts[2] === "apps" &&
        parts[3] === "detail" && parts.length === 4
      ) {
        if (request.method !== "GET") return error("Method not allowed", 405);
        const appPath = url.searchParams.get("path")?.trim();
        if (!appPath) return error("An application path is required", 400);
        if (!system.appDetail) return error("App details are unavailable", 501);

        const detail = await system.appDetail(appPath);
        if (!detail) return error("Unknown application", 404);
        return json({ data: detail });
      }

      if (pathname === "/api/system/apps/action" && request.method === "POST") {
        const body = await readJSONBody(request);
        if (!body) return error("Expected a JSON body", 400);

        const appPath = typeof body.path === "string" ? body.path.trim() : "";
        const action = typeof body.action === "string" ? body.action.trim() : "";
        const target = typeof body.target === "string" ? body.target.trim() : undefined;
        if (!appPath) return error("An application path is required", 400);
        if (!action) return error("An action is required", 400);
        if (!system.appAction) return error("App actions are unavailable", 501);

        try {
          return json({ data: await system.appAction(appPath, action, target) });
        } catch (caught) {
          if (caught instanceof AppActionError) return error(caught.message, caught.status);
          throw caught;
        }
      }

      if (pathname === "/api/media" && request.method === "POST") {
        const body = await readJSONBody(request);
        if (!body) return error("Expected a JSON body", 400);
        const action = typeof body.action === "string" ? body.action.trim() : "";
        if (!action) return error("A media action is required", 400);
        const value = typeof body.value === "number" && Number.isFinite(body.value)
          ? body.value
          : undefined;
        if (!system.control) return error("Media control is unavailable", 501);
        try {
          return json({ data: await system.control(action, value) });
        } catch (caught) {
          if (caught instanceof MediaControlError) return error(caught.message, caught.status);
          throw caught;
        }
      }

      // MARK: - Remote desktop

      if (pathname === "/api/remote" && request.method === "GET") {
        if (!remote) {
          return json({
            data: emptyRemoteStatus(
              "This hub build does not serve remote desktop. Restart it with the latest code.",
            ),
          });
        }
        return json({ data: await remote.status() });
      }

      if (pathname === "/api/remote/configure" && request.method === "POST") {
        if (!remote) return error("Remote desktop is unavailable", 501);
        const body = await readJSONBody(request);
        if (!body) return error("Expected a JSON body", 400);

        const input: RemoteConfigureInput = {};
        for (const key of ["fps", "quality", "maxWidth", "displayID"] as const) {
          const value = body[key];
          if (value === undefined) continue;
          if (typeof value !== "number" || !Number.isFinite(value)) {
            return error(`${key} must be a number`, 400);
          }
          input[key] = value;
        }
        if (Object.keys(input).length === 0) {
          return error("Provide fps, quality, maxWidth, or displayID", 400);
        }
        return json({ data: remote.configure(input) });
      }

      if (pathname === "/api/remote/permissions" && request.method === "POST") {
        if (!remote) return error("Remote desktop is unavailable", 501);
        const body = await readJSONBody(request);
        if (!body) return error("Expected a JSON body", 400);
        for (const key of ["screenRecording", "accessibility"] as const) {
          const value = body[key];
          if (value !== undefined && typeof value !== "boolean") {
            return error(`${key} must be a boolean`, 400);
          }
        }
        return json({
          data: remote.requestPermissions({
            screenRecording: body.screenRecording === true,
            accessibility: body.accessibility === true,
          }),
        });
      }

      if (
        parts[0] === "api" &&
        parts[1] === "remote" &&
        parts[2] === "socket" &&
        parts.length === 3
      ) {
        if (request.method !== "GET") return error("Method not allowed", 405);
        if (!server || !deps.remoteSockets) {
          return error("Remote desktop streams are unavailable", 501);
        }
        return deps.remoteSockets.upgrade(request, server) as Response;
      }

      // MARK: - Virtual machines

      if (pathname === "/api/vms" && request.method === "GET") {
        return withVMErrors(async () => json({ data: await vms.list() }));
      }

      if (pathname === "/api/vms/capabilities" && request.method === "GET") {
        return withVMErrors(async () => json({ data: await vms.capabilities() }));
      }

      if (pathname === "/api/vms/catalog" && request.method === "GET") {
        return withVMErrors(async () => json({ data: catalogForClient() }));
      }

      if (pathname === "/api/vms/preview" && request.method === "POST") {
        const body = await readJSONBody(request);
        if (!body) return error("Expected a JSON body", 400);
        return withVMErrors(async () => json({ data: previewDraftConfiguration(body) }));
      }

      if (pathname === "/api/vms" && request.method === "POST") {
        const body = await readJSONBody(request);
        if (!body) return error("Expected a JSON body", 400);

        const name = optionalString(body.name);
        if (name === undefined || name === null) return error("A name is required", 400);
        const channel = optionalString(body.channel);
        if (body.channel !== undefined && channel === null) {
          return error("channel must be a string", 400);
        }
        const packages = optionalStringArray(body.packages);
        if (body.packages !== undefined && packages === null) {
          return error("packages must be an array of strings", 400);
        }
        const config = optionalObject(body.config);
        if (body.config !== undefined && config === null) {
          return error("config must be an object", 400);
        }
        const cpuCount = optionalNumber(body.cpuCount);
        if (body.cpuCount !== undefined && cpuCount === null) {
          return error("cpuCount must be a number", 400);
        }
        const memoryMB = optionalNumber(body.memoryMB);
        if (body.memoryMB !== undefined && memoryMB === null) {
          return error("memoryMB must be a number", 400);
        }
        const diskGB = optionalNumber(body.diskGB);
        if (body.diskGB !== undefined && diskGB === null) {
          return error("diskGB must be a number", 400);
        }
        if (body.autostart !== undefined && typeof body.autostart !== "boolean") {
          return error("autostart must be a boolean", 400);
        }

        return withVMErrors(async () =>
          json({
            data: await vms.create({
              name,
              channel: channel ?? undefined,
              packages: packages ?? undefined,
              config: config ?? undefined,
              cpuCount: cpuCount ?? undefined,
              memoryMB: memoryMB ?? undefined,
              diskGB: diskGB ?? undefined,
              autostart: body.autostart !== false,
            }),
          }, 201),
        );
      }

      if (pathname === "/api/vms/setup") {
        if (request.method === "GET") {
          return withVMErrors(async () => json({ data: await vms.setupStatus() }));
        }
        if (request.method === "POST") {
          const body = await readJSONBody(request);
          if (!body) return error("Expected a JSON body", 400);
          const step = body.step;
          if (step !== "nix" && step !== "helper") {
            return error("step must be nix or helper", 400);
          }
          return withVMErrors(async () =>
            json({ data: await vms.startSetup(step) }, 202),
          );
        }
        return error("Method not allowed", 405);
      }

      if (pathname === "/api/vms/setup/cancel" && request.method === "POST") {
        return withVMErrors(async () => json({ data: await vms.cancelSetup() }));
      }

      if (pathname === "/api/vms/setup/logs" && request.method === "GET") {
        return withVMErrors(async () => json({ data: await vms.setupLogs() }));
      }

      if (pathname === "/api/vms/setup/log" && request.method === "GET") {
        const step = url.searchParams.get("step");
        if (step !== "nix" && step !== "helper" && step !== "builder") {
          return error("step must be nix, helper, or builder", 400);
        }
        const tail = intParam(url.searchParams.get("tail"), 240, 1, 2_000);
        return withVMErrors(async () => json({ data: await vms.setupLog(step, tail) }));
      }

      if (parts[0] === "api" && parts[1] === "vms" && parts.length >= 3) {
        const id = decodeURIComponent(parts[2]!);

        if (parts.length === 3) {
          if (request.method === "GET") {
            return withVMErrors(async () => {
              const vm = await vms.get(id, url.searchParams.get("refresh") === "1");
              return vm ? json({ data: vm }) : error("Virtual machine not found", 404);
            });
          }
          if (request.method === "PATCH") {
            const body = await readJSONBody(request);
            if (!body) return error("Expected a JSON body", 400);
            const name = optionalString(body.name);
            if (body.name !== undefined && name === null) return error("name must be a string", 400);
            const cpuCount = optionalNumber(body.cpuCount);
            if (body.cpuCount !== undefined && cpuCount === null) {
              return error("cpuCount must be a number", 400);
            }
            const memoryMB = optionalNumber(body.memoryMB);
            if (body.memoryMB !== undefined && memoryMB === null) {
              return error("memoryMB must be a number", 400);
            }
            const packages = optionalStringArray(body.packages);
            if (body.packages !== undefined && packages === null) {
              return error("packages must be an array of strings", 400);
            }
            const config = optionalObject(body.config);
            if (body.config !== undefined && config === null) {
              return error("config must be an object", 400);
            }
            if (
              name === undefined &&
              cpuCount === undefined &&
              memoryMB === undefined &&
              packages === undefined &&
              config === undefined
            ) {
              return error("Provide name, cpuCount, memoryMB, packages, or config", 400);
            }
            return withVMErrors(async () =>
              json({
                data: await vms.update(id, {
                  name: name ?? undefined,
                  cpuCount: cpuCount ?? undefined,
                  memoryMB: memoryMB ?? undefined,
                  packages: packages ?? undefined,
                  config: config ?? undefined,
                }),
              }),
            );
          }
          if (request.method === "DELETE") {
            const force = url.searchParams.get("force") === "1";
            return withVMErrors(async () => {
              await vms.remove(id, force);
              return json({ ok: true });
            });
          }
          return error("Method not allowed", 405);
        }

        if (parts.length === 4 && parts[3] === "preview" && request.method === "POST") {
          const vm = await vms.get(id, false);
          if (!vm) return error("Virtual machine not found", 404);
          const body = (await readJSONBody(request)) ?? {};
          return withVMErrors(async () => json({ data: previewConfiguration(vm, body) }));
        }

        if (parts.length === 4 && request.method === "POST") {
          const action = parts[3] as VMAction;
          if (!VM_ACTIONS.has(action)) return error("Unknown VM action", 404);
          const body = await readJSONBody(request).catch(() => null);
          const force =
            url.searchParams.get("force") === "1" || body?.force === true;
          return withVMErrors(async () => json({ data: await vms.control(id, action, force) }));
        }

        if (parts.length === 4 && parts[3] === "log" && request.method === "GET") {
          const type = (url.searchParams.get("type") ?? "build") as VMLogType;
          if (!VM_LOG_TYPES.has(type)) return error("type must be build, serial, or apply", 400);
          const tail = intParam(url.searchParams.get("tail"), 240, 1, 2_000);
          return withVMErrors(async () => json({ data: await vms.log(id, type, tail) }));
        }

        if (
          parts.length === 5 &&
          parts[3] === "console" &&
          parts[4] === "socket" &&
          request.method === "GET"
        ) {
          if (!server || !vmSockets) {
            return error("VM console streams are unavailable", 501);
          }
          return withVMErrors(async () => {
            const target = await vms.consoleTarget(id);
            return (await vmSockets.upgrade(request, server, target)) as Response;
          });
        }

        return error("Not found", 404);
      }

      // MARK: - Terminals

      if (pathname === "/api/terminals") {
        if (request.method === "GET") {
          return json({ data: await terminalStore.list(url.searchParams.get("refresh") === "1") });
        }
        if (request.method === "POST") {
          const body = await readJSONBody(request);
          if (!body) return error("Expected a JSON body", 400);

          const title = optionalString(body.title);
          if (body.title !== undefined && title === null) {
            return error("title must be a string", 400);
          }
          const cwd = optionalString(body.cwd);
          if (body.cwd !== undefined && cwd === null) {
            return error("cwd must be a string", 400);
          }
          const command = optionalString(body.command);
          if (body.command !== undefined && command === null) {
            return error("command must be a string", 400);
          }
          const location = optionalString(body.location);
          if (body.location !== undefined && location === null) {
            return error("location must be a string", 400);
          }
          const args = optionalStringArray(body.args);
          if (body.args !== undefined && args === null) {
            return error("args must be an array of strings", 400);
          }
          const env = optionalStringMap(body.env);
          if (body.env !== undefined && env === null) {
            return error("env must be an object of string values", 400);
          }

          return json({
            data: await terminalStore.create({
              title: title ?? undefined,
              cwd: cwd ?? undefined,
              command: command ?? undefined,
              args: args ?? undefined,
              location: location ?? undefined,
              env: env ?? undefined,
            }),
          });
        }
        return error("Method not allowed", 405);
      }

      if (parts[0] === "api" && parts[1] === "terminals" && parts.length === 3) {
        const id = decodeURIComponent(parts[2]!);
        if (request.method === "PUT") {
          const body = await readJSONBody(request);
          if (!body) return error("Expected a JSON body", 400);

          const title = optionalString(body.title);
          if (body.title !== undefined && title === null) {
            return error("title must be a string", 400);
          }
          const size = optionalSize(body.size);
          if (body.size !== undefined && size === null) {
            return error("size must contain positive rows and cols", 400);
          }
          const location = optionalString(body.location);
          if (body.location !== undefined && location === null) {
            return error("location must be a string", 400);
          }

          const update: TerminalUpdateInput = {};
          if (title !== null && title !== undefined) update.title = title;
          if (size !== null && size !== undefined) update.size = size;
          return json({
            data: await terminalStore.update(
              id,
              update,
              location ?? url.searchParams.get("location") ?? undefined,
            ),
          });
        }
        if (request.method === "DELETE") {
          await terminalStore.remove(
            id,
            url.searchParams.get("location") ?? undefined,
          );
          return json({ ok: true });
        }
        if (request.method === "GET") {
          const terminals = await terminalStore.list();
          const terminal = terminals.find((entry) => entry.id === id);
          return terminal ? json({ data: terminal }) : error("Terminal not found", 404);
        }
        return error("Method not allowed", 405);
      }

      if (parts[0] === "api" && parts[1] === "terminals" && parts[3] === "socket" && parts.length === 4) {
        if (request.method !== "GET") return error("Method not allowed", 405);
        if (!server || !terminalSockets) {
          return error("Terminal streams are unavailable", 501);
        }
        const id = decodeURIComponent(parts[2]!);
        // A successful upgrade returns undefined, which Bun expects; the cast
        // keeps the handler's normal Response contract for every other route.
        return (await terminalSockets.upgrade(
          request,
          server,
          id,
          url.searchParams.get("location"),
          url.searchParams.get("cursor"),
        )) as Response;
      }

      // MARK: - Terminal.app tabs

      if (pathname === "/api/host-terminals") {
        if (request.method !== "GET") return error("Method not allowed", 405);
        return json({
          data: await hostTerminals.list(url.searchParams.get("refresh") === "1"),
        });
      }

      if (parts[0] === "api" && parts[1] === "host-terminals" && parts.length === 3) {
        if (request.method !== "GET") return error("Method not allowed", 405);
        const tty = decodeURIComponent(parts[2]!);
        return json({
          data: await hostTerminals.detail(
            tty,
            url.searchParams.get("history") === "1",
          ),
        });
      }

      if (
        parts[0] === "api" &&
        parts[1] === "host-terminals" &&
        parts[3] === "command" &&
        parts.length === 4
      ) {
        if (request.method !== "POST") return error("Method not allowed", 405);
        const body = await readJSONBody(request);
        if (!body) return error("Expected a JSON body", 400);
        if (typeof body.command !== "string") {
          return error("command must be a string", 400);
        }
        const tty = decodeURIComponent(parts[2]!);
        await hostTerminals.command(tty, body.command);
        return json({ ok: true });
      }

      if (
        parts[0] === "api" &&
        parts[1] === "host-terminals" &&
        parts[3] === "focus" &&
        parts.length === 4
      ) {
        if (request.method !== "POST") return error("Method not allowed", 405);
        const tty = decodeURIComponent(parts[2]!);
        await hostTerminals.focus(tty);
        return json({ ok: true });
      }

      if (pathname === "/api/files" && request.method === "GET") {
        try {
          return json({ data: await listDirectory(url.searchParams.get("path")) });
        } catch (caught) {
          if (caught instanceof FileBrowserError) return error(caught.message, caught.status);
          throw caught;
        }
      }

      if (pathname === "/api/files/content" && request.method === "GET") {
        try {
          return json({ data: await readFileContent(url.searchParams.get("path")) });
        } catch (caught) {
          if (caught instanceof FileBrowserError) return error(caught.message, caught.status);
          throw caught;
        }
      }

      if (pathname === "/api/files/raw" && request.method === "GET") {
        try {
          const file = await readRawFile(url.searchParams.get("path"));
          return new Response(file.bytes, {
            headers: {
              "Content-Type": file.mime,
              "Content-Length": String(file.size),
              "Content-Disposition": `inline; filename*=UTF-8''${encodeURIComponent(file.name)}`,
              "Cache-Control": "no-store",
              "X-Content-Type-Options": "nosniff",
              ...CORS_HEADERS,
            },
          });
        } catch (caught) {
          if (caught instanceof FileBrowserError) return error(caught.message, caught.status);
          throw caught;
        }
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

      if (parts[0] === "api" && parts[1] === "project" && parts[3] === "git" && parts.length === 4) {
        if (request.method !== "GET") return error("Method not allowed", 405);
        const id = decodeURIComponent(parts[2]!);
        const project = db.getProject(id);
        if (!project) return error("Project not found", 404);
        const limit = intParam(url.searchParams.get("limit"), 2_000, 1, 20_000);
        return json({ data: await readProjectGit(project.canonical, limit) });
      }

      if (parts[0] === "api" && parts[1] === "project" && parts[3] === "icon" && parts.length === 4) {
        if (request.method !== "GET") return error("Method not allowed", 405);
        const id = decodeURIComponent(parts[2]!);
        const project = db.getProject(id);
        if (!project) return error("Project not found", 404);

        const icon = await resolveProjectIcon(project.canonical);
        if (!icon) return error("No icon for this project", 404);

        const etag = `"${icon.etag}"`;
        if (request.headers.get("if-none-match") === etag) {
          return new Response(null, {
            status: 304,
            headers: {
              ETag: etag,
              "Cache-Control": "public, max-age=3600",
              ...CORS_HEADERS,
            },
          });
        }

        return new Response(icon.bytes, {
          headers: {
            "Content-Type": icon.contentType,
            "Cache-Control": "public, max-age=3600",
            ETag: etag,
            ...CORS_HEADERS,
          },
        });
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

      if (pathname === "/api/model" && request.method === "GET") {
        return json({ data: await hub.models(url.searchParams.get("directory") ?? undefined) });
      }

      if (pathname === "/api/model/default" && request.method === "GET") {
        const model = await hub.defaultModel(url.searchParams.get("directory") ?? undefined);
        return json({ data: model });
      }

      if (pathname === "/api/agent" && request.method === "GET") {
        return json({ data: await hub.agents(url.searchParams.get("directory") ?? undefined) });
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

        if (parts.length === 4 && parts[3] === "forks") {
          if (request.method !== "GET") return error("Method not allowed", 405);
          return json({ data: await hub.forks(id) });
        }

        if (parts.length === 4 && parts[3] === "changes") {
          return json({ data: await hub.changes(id) });
        }

        if (parts.length === 4 && parts[3] === "git") {
          if (request.method !== "GET") return error("Method not allowed", 405);
          const session = db.getSession(id);
          if (!session) return error("Session not found", 404);
          const directory =
            session.location?.directory ?? db.getProject(session.projectID)?.canonical ?? null;
          const limit = intParam(url.searchParams.get("limit"), 2_000, 1, 20_000);
          return json({
            data: await readSessionGit(
              directory,
              session.time?.created,
              session.time?.updated,
              limit,
            ),
          });
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

        if (parts.length === 4 && parts[3] === "fork") {
          if (request.method !== "POST") return error("Method not allowed", 405);
          const body = (await readJSONBody(request)) ?? {};
          const rawBefore = (body as Record<string, unknown>).before;
          const before =
            typeof rawBefore === "string" && rawBefore.trim() ? rawBefore.trim() : null;
          return json({ data: await hub.forkSession(id, before) });
        }

        if (parts.length === 4 && parts[3] === "model") {
          if (request.method !== "POST") return error("Method not allowed", 405);
          const body = await readJSONBody(request);
          if (!body) return error("Expected a JSON body", 400);
          const model = body.model;
          if (!model || typeof model !== "object") {
            return error("A model ref is required", 400);
          }
          const fields = model as Record<string, unknown>;
          const modelID = typeof fields.id === "string" ? fields.id.trim() : "";
          const providerID = typeof fields.providerID === "string" ? fields.providerID.trim() : "";
          if (!modelID || !providerID) {
            return error("model.id and model.providerID are required", 400);
          }
          const variant = typeof fields.variant === "string" && fields.variant ? fields.variant : undefined;
          await hub.switchModel(id, { id: modelID, providerID, variant });
          return new Response(null, { status: 204, headers: CORS_HEADERS });
        }

        if (parts.length === 4 && parts[3] === "agent") {
          if (request.method !== "POST") return error("Method not allowed", 405);
          const body = await readJSONBody(request);
          if (!body) return error("Expected a JSON body", 400);
          const agent = typeof body.agent === "string" ? body.agent.trim() : "";
          if (!agent) return error("agent is required", 400);
          await hub.switchAgent(id, agent);
          return new Response(null, { status: 204, headers: CORS_HEADERS });
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
      if (caught instanceof HostTerminalError) {
        return error(caught.message, caught.status);
      }
      if (caught instanceof OpenCodeError) {
        return error(message, caught.status ?? 502);
      }
      return error(message, 500);
    }
  };
}

const VM_ACTIONS = new Set<VMAction>([
  "start",
  "stop",
  "restart",
  "pause",
  "resume",
  "rebuild",
  "apply",
]);

const VM_LOG_TYPES = new Set<VMLogType>(["build", "serial", "apply"]);

function optionalNumber(value: unknown): number | null | undefined {
  if (value === undefined || value === null) return undefined;
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function optionalString(value: unknown): string | null | undefined {
  if (value === undefined || value === null) return undefined;
  return typeof value === "string" ? value : null;
}

function optionalStringArray(value: unknown): string[] | null | undefined {
  if (value === undefined || value === null) return undefined;
  if (!Array.isArray(value) || !value.every((entry) => typeof entry === "string")) {
    return null;
  }
  return value;
}

function optionalObject(value: unknown): Record<string, unknown> | null | undefined {
  if (value === undefined || value === null) return undefined;
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function optionalStringMap(value: unknown): Record<string, string> | null | undefined {
  if (value === undefined || value === null) return undefined;
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const entries = Object.entries(value);
  if (!entries.every(([, entry]) => typeof entry === "string")) return null;
  return Object.fromEntries(entries) as Record<string, string>;
}

function optionalSize(value: unknown): { rows: number; cols: number } | null | undefined {
  if (value === undefined || value === null) return undefined;
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const { rows, cols } = value as { rows?: unknown; cols?: unknown };
  const valid = (entry: unknown): entry is number =>
    typeof entry === "number" && Number.isInteger(entry) && entry > 0 && entry <= 5_000;
  return valid(rows) && valid(cols) ? { rows, cols } : null;
}

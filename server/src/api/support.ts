import { timingSafeEqual } from "node:crypto";
import {
  MAX_EVENT_THROTTLE_MS,
  MAX_MAX_CONCURRENT_AGENTS,
  MIN_EVENT_THROTTLE_MS,
  MIN_MAX_CONCURRENT_AGENTS,
  type HubConfig,
} from "../config.ts";
import type { HubDB } from "../db.ts";
import type { ActiveSessionsResponse, HubSettings } from "../types.ts";

export interface DeviceIdentity {
  id: string;
  name: string;
  platform: string;
  appVersion: string;
}

const DEVICE_HEADER = {
  id: "x-opencodebar-device-id",
  name: "x-opencodebar-device-name",
  platform: "x-opencodebar-platform",
  appVersion: "x-opencodebar-app-version",
} as const;

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Last-Event-ID",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

export function deviceFromRequest(request: Request): DeviceIdentity | null {
  const id = request.headers.get(DEVICE_HEADER.id)?.trim();
  if (!id) return null;
  const clean = (value: string | null, fallback: string): string => {
    const trimmed = value?.trim();
    return trimmed ? trimmed.slice(0, 120) : fallback;
  };
  return {
    id: id.slice(0, 120),
    name: clean(request.headers.get(DEVICE_HEADER.name), "Unknown device"),
    platform: clean(request.headers.get(DEVICE_HEADER.platform), "unknown"),
    appVersion: clean(request.headers.get(DEVICE_HEADER.appVersion), ""),
  };
}

export function json(data: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...CORS_HEADERS,
      ...extra,
    },
  });
}

export function error(message: string, status = 400): Response {
  return json({ error: { message } }, status);
}

export interface JSONBody {
  [key: string]: unknown;
}

/** Reads a JSON object body, returning null when the payload is malformed. */
export async function readJSONBody(request: Request): Promise<JSONBody | null> {
  try {
    const value: unknown = await request.json();
    return value && typeof value === "object" && !Array.isArray(value)
      ? (value as JSONBody)
      : null;
  } catch {
    return null;
  }
}

function safeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a, "utf8");
  const right = Buffer.from(b, "utf8");
  if (left.length !== right.length) return false;
  return timingSafeEqual(left, right);
}

export function isAuthorized(request: Request, token: string): boolean {
  const header = request.headers.get("authorization") ?? "";
  const bearer = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : "";
  const query = new URL(request.url).searchParams.get("token") ?? "";
  return safeEqual(bearer || query, token);
}

export function intParam(value: string | null, fallback: number, min: number, max: number): number {
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(parsed, min), max);
}

export function settingsPayload(config: HubConfig, preventSleepSupported: boolean): HubSettings {
  return {
    eventThrottleMs: config.eventThrottleMs,
    eventThrottleMinMs: MIN_EVENT_THROTTLE_MS,
    eventThrottleMaxMs: MAX_EVENT_THROTTLE_MS,
    preventSleep: config.preventSleep,
    preventSleepSupported,
    maxConcurrentAgents: config.maxConcurrentAgents,
    maxConcurrentAgentsMin: MIN_MAX_CONCURRENT_AGENTS,
    maxConcurrentAgentsMax: MAX_MAX_CONCURRENT_AGENTS,
  };
}

export function activeResponse(db: HubDB): ActiveSessionsResponse {
  const active = db.getSessions({ active: true, limit: 5_000 });
  const data: Record<string, { type: string }> = {};
  for (const session of active) data[session.id] = { type: "running" };
  return { data };
}

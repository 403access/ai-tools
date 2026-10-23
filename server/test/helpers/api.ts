import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHandler } from "../../src/api.ts";
import type { HubConfig } from "../../src/config.ts";
import { HubDB } from "../../src/db.ts";
import { Hub } from "../../src/hub.ts";
import type { HubEvent, Session } from "../../src/types.ts";

export const TOKEN = "test-token";

export function config(overrides: Partial<HubConfig> = {}): HubConfig {
  return {
    host: "127.0.0.1",
    port: 8787,
    token: TOKEN,
    dbPath: ":memory:",
    configPath: "/tmp/opencodebar-hub-test.json",
    goUsageURL: "https://example.invalid/usage",
    fastPollMs: 5_000,
    slowPollMs: 60_000,
    usagePollMs: 60_000,
    // Tests assert deliveries directly, so keep the default un-throttled.
    eventThrottleMs: 0,
    logLevel: "warn",
    ...overrides,
  };
}

export function session(id: string, updated: number, overrides: Partial<Session> = {}): Session {
  return {
    id,
    projectID: "prj_1",
    cost: 0.1,
    tokens: { input: 1, output: 2, reasoning: 0, cache: { read: 0, write: 0 } },
    time: { created: 1, updated },
    title: `Session ${id}`,
    location: { directory: "/tmp/project" },
    ...overrides,
  };
}

export function setup(overrides: Partial<HubConfig> = {}) {
  const db = new HubDB(":memory:");
  const cfg = config(overrides);
  const hub = new Hub(cfg, db, {
    discover: async () => null,
    usageFetcher: async () => ({ rolling: { percent: 12 } }),
  });
  const handler = createHandler({ db, hub, config: cfg });
  return { db, hub, handler };
}

export function request(path: string, init: RequestInit = {}, token: string | null = TOKEN): Request {
  const headers = new Headers(init.headers);
  if (token) headers.set("Authorization", `Bearer ${token}`);
  return new Request(`http://127.0.0.1:8787${path}`, { ...init, headers });
}

export async function body<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

export interface SessionList {
  data: Session[];
}

export interface ActiveList {
  data: Record<string, { type: string }>;
}

export interface MessagePage {
  data: Array<{ id: string }>;
  cursor?: { previous?: string; next?: string };
}


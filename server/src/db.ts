import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type {
  ConnectedDevice,
  FileDiff,
  GoUsage,
  Project,
  Session,
  SessionMessage,
  SessionStats,
  Stats,
  SyncResponse,
  TokenUsage,
} from "./types.ts";
import { getDevices, upsertDevice } from "./db/devices.ts";
import {
  getChanges,
  getMessageCount,
  getMessageSync,
  getMessages,
  getMessagesSince,
  getProjectChanges,
  putMessageSync,
  upsertMessages,
  type MessagePage,
  type MessageSync,
} from "./db/messages.ts";
import {
  getProject,
  getProjects,
  replaceProjects,
  upsertProjects,
  type ChangeLog,
} from "./db/projects.ts";
import { migrate } from "./db/schema.ts";
import { getActiveSessionIDs, getForks as getSessionForks, getSession, getSessions, markActive, setActive, updateSessionUsage, upsertSessions, type SessionQuery } from "./db/sessions.ts";
import { recordTaskPrompt, setTaskStatus } from "./db/tasks.ts";
import { getSessionStats } from "./db/sessionStats.ts";
import { counts, getStats, getUsage, putStats, putUsage, putUsageError, type CachedStats, type CachedUsage } from "./db/stats.ts";
import { getSync } from "./db/sync.ts";

export { parseFileDiffs, toolOutcome } from "./db/parsing.ts";
export { decodeMessageCursor, encodeMessageCursor } from "./db/cursor.ts";
export { parseTokens, rowToMessage, rowToProject, rowToSession } from "./db/rows.ts";
export { DEVICE_STALE_MS } from "./db/devices.ts";
export type { MessagePage } from "./db/messages.ts";
export type { MessageSync } from "./db/messages.ts";
export type { SessionQuery } from "./db/sessions.ts";
export type { CachedStats, CachedUsage } from "./db/stats.ts";

export class HubDB implements ChangeLog {
  readonly db: Database;
  readonly path: string;

  constructor(path: string) {
    this.path = path;
    if (path !== ":memory:") {
      mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    }
    this.db = new Database(path, { create: true });
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec("PRAGMA foreign_keys = ON;");
    this.db.exec("PRAGMA busy_timeout = 5000;");
    migrate(this.db);
  }

  /**
   * Appends one row to the incremental sync feed. Clients ask for everything
   * with a revision greater than their own, so only real changes are logged.
   */
  logChange(kind: "session" | "project", id: string, deleted = false): void {
    const result = this.db
      .prepare("INSERT INTO sync_log (kind, entity_id, deleted) VALUES (?, ?, ?)")
      .run(kind, id, deleted ? 1 : 0);
    // Amortise pruning so the feed stays bounded without a count per write.
    if (Number(result.lastInsertRowid) % 10_000 === 0) this.pruneSyncLog();
  }

  private pruneSyncLog(keep = 50_000): void {
    this.db
      .prepare("DELETE FROM sync_log WHERE rev <= (SELECT MAX(rev) - ? FROM sync_log)")
      .run(keep);
  }

  close(): void {
    this.db.close();
  }

  // MARK: - Devices

  upsertDevice(
    device: { id: string; name: string; platform: string; appVersion: string },
    now = Date.now(),
  ): void {
    upsertDevice(this.db, device, now);
  }

  getDevices(limit = 50): ConnectedDevice[] {
    return getDevices(this.db, limit);
  }

  // MARK: - Projects

  replaceProjects(projects: Project[], now = Date.now()): void {
    replaceProjects(this.db, this, projects, now);
  }

  upsertProjects(projects: Project[], now = Date.now()): void {
    upsertProjects(this.db, this, projects, now);
  }

  getProjects(): Project[] {
    return getProjects(this.db);
  }

  getProject(id: string): Project | null {
    return getProject(this.db, id);
  }

  // MARK: - Sessions

  upsertSessions(sessions: Session[], now = Date.now()): void {
    upsertSessions(this.db, this, sessions, now);
  }

  setActive(ids: Set<string>, now = Date.now()): void {
    setActive(this.db, ids, now);
  }

  markActive(id: string, active: boolean, now = Date.now()): void {
    markActive(this.db, id, active, now);
  }

  updateSessionUsage(id: string, cost: number | undefined, tokens: TokenUsage | undefined, now = Date.now()): void {
    updateSessionUsage(this.db, this, id, cost, tokens, now);
  }

  getSessions(query: SessionQuery = {}): Session[] {
    return getSessions(this.db, query);
  }

  getSession(id: string): Session | null {
    return getSession(this.db, id);
  }

  getTasks(limit = 500, project?: string): Session[] {
    return getSessions(this.db, { tasksOnly: true, limit, project });
  }

  setTaskStatus(id: string, status: "open" | "done" | "dismissed", now = Date.now()): Session | null {
    return setTaskStatus(this.db, this, id, status, now);
  }

  recordTaskPrompt(id: string, prompt: string, now = Date.now()): void {
    recordTaskPrompt(this.db, this, id, prompt, now);
  }

  getForks(sessionID: string, limit = 50): Session[] {
    return getSessionForks(this.db, sessionID, limit);
  }

  getActiveSessionIDs(): string[] {
    return getActiveSessionIDs(this.db);
  }

  getSync(since?: number): SyncResponse {
    return getSync(this.db, since);
  }

  // MARK: - Messages

  upsertMessages(sessionID: string, messages: SessionMessage[], now = Date.now()): void {
    upsertMessages(this.db, sessionID, messages, now);
  }

  getChanges(sessionID: string): FileDiff[] {
    return getChanges(this.db, sessionID);
  }

  getProjectChanges(projectID: string, limit = 2_000): FileDiff[] {
    return getProjectChanges(this.db, projectID, limit);
  }

  getMessageSync(sessionID: string): MessageSync | null {
    return getMessageSync(this.db, sessionID);
  }

  putMessageSync(sessionID: string, sync: MessageSync): void {
    putMessageSync(this.db, sessionID, sync);
  }

  getMessages(sessionID: string, limit = 100, cursor?: string | null): MessagePage {
    return getMessages(this.db, sessionID, limit, cursor);
  }

  getMessagesSince(sessionID: string, since: number, limit = 500): SessionMessage[] {
    return getMessagesSince(this.db, sessionID, since, limit);
  }

  getMessageCount(sessionID: string): number {
    return getMessageCount(this.db, sessionID);
  }

  getSessionStats(sessionID: string): SessionStats | null {
    return getSessionStats(this.db, sessionID);
  }

  // MARK: - Stats and usage

  putStats(scope: string, payload: Stats, now = Date.now()): void {
    putStats(this.db, scope, payload, now);
  }

  getStats(scope: string): CachedStats | null {
    return getStats(this.db, scope);
  }

  putUsage(payload: GoUsage | null, fetchedAt: number | null, error: string | null, now = Date.now()): void {
    putUsage(this.db, payload, fetchedAt, error, now);
  }

  putUsageError(error: string, now = Date.now()): void {
    putUsageError(this.db, error, now);
  }

  getUsage(): CachedUsage {
    return getUsage(this.db);
  }

  counts(): { sessions: number; messages: number; projects: number } {
    return counts(this.db);
  }
}

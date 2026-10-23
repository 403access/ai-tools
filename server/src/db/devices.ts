import type { Database } from "bun:sqlite";
import type { ConnectedDevice } from "../types.ts";
import { number, text, type Row } from "./rows.ts";

/**
 * How long after its last request a device stops counting as connected. Also
 * used when merging stale device rows, so a genuinely live device with the same
 * name is never collapsed into another one.
 */
export const DEVICE_STALE_MS = 20_000;

/** Records a client app that has contacted the hub, keeping first-seen. */
export function upsertDevice(
  db: Database,
  device: { id: string; name: string; platform: string; appVersion: string },
  now = Date.now(),
): void {
  const run = db.transaction(() => {
    const existing = db.query("SELECT first_seen FROM devices WHERE id = ?").get(device.id) as Row | null;
    let firstSeen = existing ? number(existing.first_seen, now) : now;

    // Older clients generated a new random id after every reinstall or
    // rebuild, which left a stale "disconnected" row behind. Fold those
    // legacy rows into this device so reconnecting never produces a
    // duplicate. Ids with the `dev-` stable prefix are never merged with
    // another row: they may be a different device that shares a name.
    const legacyRows = db
      .query(
        `SELECT id, first_seen FROM devices
         WHERE id != ? AND id NOT LIKE 'dev-%'
           AND name = ? AND platform = ? AND last_seen < ?`,
      )
      .all(device.id, device.name, device.platform, now - DEVICE_STALE_MS) as Row[];
    const remove = db.prepare("DELETE FROM devices WHERE id = ?");
    for (const row of legacyRows) {
      firstSeen = Math.min(firstSeen, number(row.first_seen, now));
      remove.run(String(row.id));
    }

    db.prepare(`
      INSERT INTO devices (id, name, platform, app_version, first_seen, last_seen)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        platform = excluded.platform,
        app_version = excluded.app_version,
        last_seen = excluded.last_seen
    `).run(device.id, device.name, device.platform, device.appVersion, firstSeen, now);
  });
  run();
}

export function getDevices(db: Database, limit = 50): ConnectedDevice[] {
  const rows = db
    .query("SELECT * FROM devices ORDER BY last_seen DESC LIMIT ?")
    .all(limit) as Row[];
  return rows.map((row) => ({
    id: String(row.id),
    name: text(row.name) ?? "Unknown device",
    platform: text(row.platform) ?? "unknown",
    appVersion: text(row.app_version) ?? "",
    firstSeen: number(row.first_seen),
    lastSeen: number(row.last_seen),
    // The hub fills in the live connection state; stored rows are history.
    connected: false,
  }));
}

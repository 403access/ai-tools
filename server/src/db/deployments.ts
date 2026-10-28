import type { Database } from "bun:sqlite";
import type { Deployment, DeploymentDevice } from "../types.ts";
import { number, optionalNumber, text, type Row } from "./rows.ts";

/** Bundle prefix shared by the normal iOS app and its side-by-side variants. */
export const MOBILE_BUNDLE_PREFIX = "dev.opencodebar.mobile";

/** True for the app bundle and variants, false for the widget extension. */
export function isMobileBundle(bundleId: string): boolean {
  if (!bundleId.startsWith(MOBILE_BUNDLE_PREFIX)) return false;
  const rest = bundleId.slice(MOBILE_BUNDLE_PREFIX.length);
  return !rest.endsWith(".widgets");
}

/** `dev.opencodebar.mobile.review-a` → `review-a`; the normal app → "". */
export function variantFromBundle(bundleId: string): string {
  const rest = bundleId.slice(MOBILE_BUNDLE_PREFIX.length);
  return rest.startsWith(".") ? rest.slice(1) : "";
}

export interface DeploymentInput {
  deviceKey: string;
  deviceName: string;
  deviceModel?: string;
  bundleId: string;
  appName?: string;
  variant?: string;
  version?: string;
  build?: string;
  commitSha?: string;
  branch?: string;
  worktree?: string;
  source?: "script" | "sync";
  installedAt?: number;
}

export interface SyncedApp {
  bundleId: string;
  appName: string;
  version: string;
  build: string;
}

function rowToDeployment(row: Row): Deployment {
  const deployment: Deployment = {
    id: String(row.id),
    deviceKey: String(row.device_key ?? ""),
    deviceName: text(row.device_name) ?? "",
    deviceModel: text(row.device_model) ?? "",
    bundleId: String(row.bundle_id ?? ""),
    appName: text(row.app_name) ?? "",
    variant: text(row.variant) ?? "",
    version: text(row.version) ?? "",
    build: text(row.build) ?? "",
    commitSha: text(row.commit_sha) ?? "",
    branch: text(row.branch) ?? "",
    worktree: text(row.worktree) ?? "",
    source: text(row.source) === "sync" ? "sync" : "script",
    installedAt: number(row.installed_at),
  };
  const endedAt = optionalNumber(row.ended_at);
  if (endedAt !== undefined) deployment.endedAt = endedAt;
  const reason = text(row.end_reason);
  if (reason === "replaced" || reason === "uninstalled") deployment.endReason = reason;
  return deployment;
}

function rowToDevice(row: Row): DeploymentDevice {
  const device: DeploymentDevice = {
    key: String(row.key ?? ""),
    name: text(row.name) ?? "Unknown device",
    model: text(row.model) ?? "",
    platform: text(row.platform) ?? "",
    state: text(row.state) ?? "",
    connected: false,
    current: [],
  };
  const synced = optionalNumber(row.last_synced);
  if (synced !== undefined && synced > 0) device.lastSynced = synced;
  return device;
}

/** Stores a device seen by a scan, even when it has no OpenCodeBar build. */
export function upsertDeploymentDevice(
  db: Database,
  device: { key: string; name: string; model?: string; platform?: string; state?: string },
  now = Date.now(),
  synced = true,
): void {
  db.prepare(`
    INSERT INTO deployment_devices (key, name, model, platform, state, last_synced)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(key) DO UPDATE SET
      name = excluded.name,
      model = CASE WHEN excluded.model = '' THEN deployment_devices.model ELSE excluded.model END,
      platform = CASE WHEN excluded.platform = '' THEN deployment_devices.platform ELSE excluded.platform END,
      state = CASE WHEN excluded.state = '' THEN deployment_devices.state ELSE excluded.state END,
      last_synced = CASE WHEN ? = 1 THEN excluded.last_synced ELSE deployment_devices.last_synced END
  `).run(
    device.key,
    device.name,
    device.model ?? "",
    device.platform ?? "iOS",
    device.state ?? "",
    synced ? now : 0,
    synced ? 1 : 0,
  );
}

function closeOpenRows(
  db: Database,
  deviceKey: string,
  bundleId: string,
  now: number,
  reason: "replaced" | "uninstalled",
): void {
  db.prepare(
    `UPDATE deployments
     SET ended_at = ?, end_reason = ?
     WHERE device_key = ? AND bundle_id = ? AND ended_at IS NULL`,
  ).run(now, reason, deviceKey, bundleId);
}

/**
 * Records one install. The previous build for the same bundle on the same
 * device is closed as replaced, so the open row is always "installed now".
 */
export function recordDeployment(
  db: Database,
  input: DeploymentInput,
  now = Date.now(),
): Deployment {
  const installedAt = input.installedAt ?? now;
  const id = crypto.randomUUID();
  const bundleId = input.bundleId.trim();
  const deviceKey = input.deviceKey.trim();
  if (!deviceKey || !bundleId) {
    throw new Error("deviceKey and bundleId are required");
  }

  const run = db.transaction(() => {
    closeOpenRows(db, deviceKey, bundleId, installedAt, "replaced");
    db.prepare(`
      INSERT INTO deployments (
        id, device_key, device_name, device_model, bundle_id, app_name, variant,
        version, build, commit_sha, branch, worktree, source, installed_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id,
      deviceKey,
      input.deviceName,
      input.deviceModel ?? "",
      bundleId,
      input.appName ?? "",
      input.variant ?? variantFromBundle(bundleId),
      input.version ?? "",
      input.build ?? "",
      input.commitSha ?? "",
      input.branch ?? "",
      input.worktree ?? "",
      input.source ?? "script",
      installedAt,
    );
    // Keep the device row in sync with the latest report.
    upsertDeploymentDevice(
      db,
      {
        key: deviceKey,
        name: input.deviceName,
        model: input.deviceModel,
      },
      now,
    );
  });
  run();

  const row = db.query("SELECT * FROM deployments WHERE id = ?").get(id) as Row;
  return rowToDeployment(row);
}

/**
 * Reconciles one device with the apps it currently has installed. Builds that
 * disappeared are closed as uninstalled; new or changed builds become rows
 * attributed to the scan.
 */
export function syncDeploymentDevice(
  db: Database,
  device: { key: string; name: string; model?: string; platform?: string; state?: string },
  apps: SyncedApp[],
  now = Date.now(),
): void {
  const installed = new Map(
    apps
      .filter((app) => isMobileBundle(app.bundleId))
      .map((app) => [app.bundleId, app] as const),
  );

  const run = db.transaction(() => {
    upsertDeploymentDevice(db, device, now);

    const open = db
      .query("SELECT * FROM deployments WHERE device_key = ? AND ended_at IS NULL")
      .all(device.key) as Row[];

    for (const row of open) {
      const bundleId = String(row.bundle_id ?? "");
      if (!installed.has(bundleId)) {
        closeOpenRows(db, device.key, bundleId, now, "uninstalled");
      }
    }

    for (const app of installed.values()) {
      const current = open.find((row) => String(row.bundle_id) === app.bundleId);
      if (current) {
        const version = String(current.version ?? "");
        const build = String(current.build ?? "");
        // A script report may not have read the bundle metadata; fill it in
        // instead of replacing a row that already carries the commit.
        if ((!version || version === app.version) && (!build || build === app.build)) {
          if (!version || !build || !String(current.app_name ?? "")) {
            db.prepare(
              `UPDATE deployments
               SET version = ?, build = ?, app_name = ?
               WHERE id = ?`,
            ).run(app.version, app.build, app.appName, String(current.id));
          }
          continue;
        }
        closeOpenRows(db, device.key, app.bundleId, now, "replaced");
      }
      db.prepare(`
        INSERT INTO deployments (
          id, device_key, device_name, device_model, bundle_id, app_name, variant,
          version, build, commit_sha, branch, worktree, source, installed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '', '', '', 'sync', ?)
      `).run(
        crypto.randomUUID(),
        device.key,
        device.name,
        device.model ?? "",
        app.bundleId,
        app.appName,
        variantFromBundle(app.bundleId),
        app.version,
        app.build,
        now,
      );
    }
  });
  run();
}

export function getDeployments(db: Database, limit = 200): Deployment[] {
  const rows = db
    .query("SELECT * FROM deployments ORDER BY installed_at DESC, rowid DESC LIMIT ?")
    .all(Math.max(1, Math.min(limit, 2_000))) as Row[];
  return rows.map(rowToDeployment);
}

export function getDeploymentDevices(db: Database): DeploymentDevice[] {
  const rows = db
    .query("SELECT * FROM deployment_devices ORDER BY last_synced DESC")
    .all() as Row[];
  return rows.map(rowToDevice);
}

/** Open rows (installed now) grouped by device key. */
export function getCurrentDeployments(db: Database): Map<string, Deployment[]> {
  const rows = db
    .query("SELECT * FROM deployments WHERE ended_at IS NULL ORDER BY installed_at DESC, rowid DESC")
    .all() as Row[];
  const grouped = new Map<string, Deployment[]>();
  for (const row of rows) {
    const deployment = rowToDeployment(row);
    const list = grouped.get(deployment.deviceKey) ?? [];
    list.push(deployment);
    grouped.set(deployment.deviceKey, list);
  }
  return grouped;
}

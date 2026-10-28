import type { Hub } from "../hub.ts";
import type { DeploymentDevice, DeploymentsPayload } from "../types.ts";
import {
  DeploymentScanError,
  installedApps,
  listPhysicalDevices,
  type PhysicalDevice,
} from "../deployments.ts";
import { devices as connectedDevices } from "./reads.ts";

/** Devices and open deployments, with the hub's live connection flag merged in. */
export function deploymentsPayload(hub: Hub, limit = 200): DeploymentsPayload {
  const current = hub.db.getCurrentDeployments();
  const live = connectedDevices(hub);
  const byName = new Map(live.map((device) => [device.name.trim().toLowerCase(), device]));

  const devices = hub.db.getDeploymentDevices().map((device): DeploymentDevice => {
    const match = byName.get(device.name.trim().toLowerCase());
    return {
      ...device,
      connected: match?.connected ?? false,
      ...(match ? { lastSeen: match.lastSeen } : {}),
      current: current.get(device.key) ?? [],
    };
  });

  // A script can report a device before a scan ever stores its row.
  const known = new Set(devices.map((device) => device.key));
  for (const [key, rows] of current) {
    if (known.has(key)) continue;
    const first = rows[0];
    devices.push({
      key,
      name: first?.deviceName || "Unknown device",
      model: first?.deviceModel ?? "",
      platform: "iOS",
      state: "",
      connected: false,
      current: rows,
    });
  }

  devices.sort((a, b) => {
    if (a.connected !== b.connected) return a.connected ? -1 : 1;
    return a.name.localeCompare(b.name);
  });

  const syncedAt = devices.reduce(
    (latest, device) => Math.max(latest, device.lastSynced ?? 0),
    0,
  );
  return {
    devices,
    deployments: hub.db.getDeployments(limit),
    ...(syncedAt > 0 ? { syncedAt } : {}),
  };
}

export interface DeploymentScanResult {
  payload: DeploymentsPayload;
  errors: string[];
}

let inFlight: Promise<DeploymentScanResult> | null = null;

/**
 * Reads every paired iPhone/iPad with devicectl and reconciles the database.
 * Concurrent clicks share one scan; each device is scanned independently so a
 * sleeping phone does not hide the others.
 */
export function scanDeployments(hub: Hub): Promise<DeploymentScanResult> {
  if (inFlight) return inFlight;
  inFlight = runScan(hub).finally(() => {
    inFlight = null;
  });
  return inFlight;
}

async function runScan(hub: Hub): Promise<DeploymentScanResult> {
  let physical: PhysicalDevice[];
  try {
    physical = await listPhysicalDevices();
  } catch (caught) {
    throw caught instanceof DeploymentScanError
      ? caught
      : new DeploymentScanError(String(caught));
  }

  const errors: string[] = [];
  for (const device of physical) {
    const now = Date.now();
    try {
      const apps = await installedApps(device.key);
      // Store the device even when no OpenCodeBar build is installed, so the
      // settings screen can show "nothing installed" instead of hiding it.
      hub.db.syncDeploymentDevice(device, apps, now);
    } catch (caught) {
      // Keep the device visible with its current state, but do not pretend the
      // app list was read: lastSynced stays at the last successful scan.
      hub.db.upsertDeploymentDevice(device, now, false);
      errors.push(`${device.name}: ${caught instanceof Error ? caught.message : String(caught)}`);
    }
  }

  return { payload: deploymentsPayload(hub), errors };
}

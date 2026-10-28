import { execFile } from "node:child_process";

/**
 * Reads physical iOS devices and the apps installed on them through
 * `xcrun devicectl`. The hub runs on the Mac that installs the builds, so this
 * is the authoritative "what is on the phone right now" source; the install
 * script only adds the commit and branch that devicectl cannot report.
 */

export interface PhysicalDevice {
  /** UDID when available, otherwise the devicectl identifier. */
  key: string;
  name: string;
  model: string;
  /** iOS or iPadOS. */
  platform: string;
  /** devicectl connection state: connected, available, unavailable. */
  state: string;
}

export interface InstalledApp {
  bundleId: string;
  appName: string;
  version: string;
  build: string;
}

export class DeploymentScanError extends Error {}

interface CommandResult {
  ok: boolean;
  stdout: string;
  stderr: string;
}

function run(args: string[], timeoutMs: number): Promise<CommandResult> {
  return new Promise((resolve) => {
    execFile(
      "xcrun",
      args,
      { timeout: timeoutMs, maxBuffer: 32 * 1024 * 1024, encoding: "utf8" },
      (error, stdout, stderr) => {
        resolve({
          ok: !error,
          stdout: typeof stdout === "string" ? stdout : "",
          stderr: typeof stderr === "string" ? stderr : "",
        });
      },
    );
  });
}

function parseJSON(output: string): unknown {
  const start = output.indexOf("{");
  if (start < 0) return null;
  try {
    return JSON.parse(output.slice(start));
  } catch {
    return null;
  }
}

function firstLine(value: string): string | undefined {
  return value
    .split("\n")
    .map((line) => line.trim())
    .find((line) => line.length > 0);
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function string(value: unknown): string {
  return typeof value === "string" ? value : "";
}

/** Physical iOS/iPadOS devices known to this Mac, paired or connected. */
export async function listPhysicalDevices(): Promise<PhysicalDevice[]> {
  const result = await run(["devicectl", "list", "devices", "--json-output", "-"], 20_000);
  if (!result.ok) {
    throw new DeploymentScanError(
      firstLine(result.stderr) ??
        "devicectl could not list devices. Install Xcode and connect an iPhone or iPad.",
    );
  }
  const data = parseJSON(result.stdout);
  const devices = (record(record(data).result).devices as unknown[]) ?? [];
  if (!Array.isArray(devices)) {
    throw new DeploymentScanError("devicectl returned unreadable device data.");
  }

  const physical: PhysicalDevice[] = [];
  for (const entry of devices) {
    const item = record(entry);
    const properties = record(item.properties);
    const hardware = record(properties.hardware ?? item.hardwareProperties);
    const connection = record(properties.connection ?? item.connectionProperties);
    const details = record(item.deviceProperties);
    if (string(hardware.platform) !== "iOS" || string(hardware.reality) !== "physical") {
      continue;
    }
    const udid = string(hardware.udid);
    const identifier = string(item.identifier);
    const key = udid || identifier;
    if (!key) continue;
    const deviceType = string(hardware.deviceType);
    physical.push({
      key,
      name: string(details.name) || string(item.name) || string(hardware.marketingName) || "Device",
      model: string(hardware.marketingName) || string(hardware.productType),
      platform: deviceType === "iPad" ? "iPadOS" : "iOS",
      state: string(connection.state) || "unknown",
    });
  }
  return physical;
}

/** Apps currently installed on one device, as reported by devicectl. */
export async function installedApps(deviceKey: string): Promise<InstalledApp[]> {
  const result = await run(
    ["devicectl", "device", "info", "apps", "--device", deviceKey, "--json-output", "-"],
    30_000,
  );
  if (!result.ok) {
    throw new DeploymentScanError(
      firstLine(result.stderr) ??
        `Could not read installed apps on ${deviceKey}. Keep the device unlocked and nearby.`,
    );
  }
  const data = parseJSON(result.stdout);
  const apps = (record(record(data).result).apps as unknown[]) ?? [];
  if (!Array.isArray(apps)) {
    throw new DeploymentScanError(`devicectl returned unreadable app data for ${deviceKey}.`);
  }
  return apps.map((entry) => {
    const app = record(entry);
    return {
      bundleId: string(app.bundleIdentifier),
      appName: string(app.name),
      version: string(app.version),
      build: string(app.bundleVersion),
    };
  });
}

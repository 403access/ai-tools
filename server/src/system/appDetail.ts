import { readdirSync, statSync } from "node:fs";
import { basename, extname, join } from "node:path";
import type {
  SystemApp,
  SystemAppDetail,
  SystemAppExtension,
  SystemAppInfo,
  SystemAppSigning,
  SystemSimulatorDevice,
  SystemSimulatorRuntime,
  SystemXcodeDetail,
  SystemXcodeFramework,
  SystemXcodeSDK,
} from "../types.ts";
import { COMMAND_TIMEOUT_MS, LONG_COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import {
  asRecord,
  lines,
  numberValue,
  parseJSON,
  parseJSONValue,
  stringValue,
  text,
  unique,
} from "./util.ts";

/**
 * Detail pages for installed applications. The generic part reads the bundle's
 * Info.plist, signing identity, extensions and size. Apps with a dedicated
 * provider add their own inventory; Xcode gets simulator runtimes/devices, SDKs
 * and the frameworks shipped in its developer directory, plus the management
 * actions that operate on simulators.
 */

export class AppActionError extends Error {
  readonly status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.name = "AppActionError";
    this.status = status;
  }
}

export function isXcodeApp(app: SystemApp): boolean {
  if (app.bundleID === "com.apple.dt.Xcode") return true;
  return /^xcode(?:-|$|\s)/i.test(app.name);
}

export async function collectAppDetail(
  run: CommandRunner,
  app: SystemApp,
): Promise<SystemAppDetail> {
  const info = await collectAppInfo(run, app);
  const xcode = isXcodeApp(app) ? await collectXcodeDetail(run, app) : undefined;
  return {
    app,
    info,
    xcode,
    generatedAt: Date.now(),
  };
}

async function readBundlePlist(
  run: CommandRunner,
  path: string,
): Promise<Record<string, unknown> | null> {
  const result = await run(
    "/usr/bin/plutil",
    ["-convert", "json", "-o", "-", path],
    COMMAND_TIMEOUT_MS,
  );
  if (!result.ok) return null;
  return parseJSON(result.stdout);
}

function appBundleLayout(appPath: string): {
  contents: string;
  infoPlist: string;
  resources: string;
} | null {
  if (!appPath.endsWith(".app")) return null;
  const contents = join(appPath, "Contents");
  return {
    contents,
    infoPlist: join(contents, "Info.plist"),
    resources: join(contents, "Resources"),
  };
}

async function collectAppInfo(run: CommandRunner, app: SystemApp): Promise<SystemAppInfo> {
  const layout = appBundleLayout(app.path);
  const plist = layout ? await readBundlePlist(run, layout.infoPlist) : null;
  const info: SystemAppInfo = {
    displayName: stringValue(plist?.CFBundleDisplayName) ?? stringValue(plist?.CFBundleName),
    bundleID: stringValue(plist?.CFBundleIdentifier) ?? app.bundleID,
    version:
      stringValue(plist?.CFBundleShortVersionString) ??
      app.version ??
      stringValue(plist?.CFBundleVersion),
    build: stringValue(plist?.CFBundleVersion),
    minimumOS: stringValue(plist?.LSMinimumSystemVersion),
    copyright: stringValue(plist?.NSHumanReadableCopyright),
    executable: stringValue(plist?.CFBundleExecutable),
    extensions: layout ? bundledExtensions(app.path) : [],
    signing: await collectSigning(run, app.path),
  };

  if (plist) {
    info.urlSchemes = urlSchemes(plist);
    info.documentTypes = documentTypes(plist);
  }

  info.sizeBytes = await measureSize(run, app.path);
  return info;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.map(stringValue).filter((entry): entry is string => Boolean(entry))
    : [];
}

function urlSchemes(plist: Record<string, unknown>): string[] {
  const types = Array.isArray(plist.CFBundleURLTypes) ? plist.CFBundleURLTypes : [];
  const schemes: string[] = [];
  for (const raw of types) {
    const entry = asRecord(raw);
    schemes.push(...stringArray(entry?.CFBundleURLSchemes));
  }
  return unique(schemes).slice(0, 20);
}

function documentTypes(plist: Record<string, unknown>): string[] {
  const types = Array.isArray(plist.CFBundleDocumentTypes) ? plist.CFBundleDocumentTypes : [];
  const names: string[] = [];
  for (const raw of types) {
    const entry = asRecord(raw);
    const name = stringValue(entry?.CFBundleTypeName);
    if (name) names.push(name);
    names.push(...stringArray(entry?.CFBundleTypeExtensions));
  }
  return unique(names).slice(0, 20);
}

function bundledExtensions(appPath: string): SystemAppExtension[] {
  const contents = join(appPath, "Contents");
  const roots: Array<{ path: string; kind: SystemAppExtension["kind"] }> = [
    { path: join(contents, "PlugIns"), kind: "extension" },
    { path: join(contents, "XPCServices"), kind: "xpc" },
    { path: join(contents, "Library", "SystemExtensions"), kind: "extension" },
    { path: join(contents, "Library", "LoginItems"), kind: "login-item" },
  ];
  const extensions: SystemAppExtension[] = [];

  for (const root of roots) {
    for (const entry of listDirectory(root.path)) {
      const extension = extname(entry).toLowerCase();
      if (![".appex", ".xpc", ".app", ".systemextension"].includes(extension)) continue;
      extensions.push({
        name: basename(entry, extname(entry)),
        path: join(root.path, entry),
        kind: root.kind,
      });
    }
  }
  return extensions;
}

function listDirectory(path: string): string[] {
  try {
    return readdirSync(path).filter((entry) => !entry.startsWith("."));
  } catch {
    return [];
  }
}

async function measureSize(run: CommandRunner, path: string): Promise<number | undefined> {
  const result = await run("du", ["-sk", path], LONG_COMMAND_TIMEOUT_MS);
  if (!result.ok) return undefined;
  const kilobytes = numberValue(text(result).split(/\s+/)[0]);
  return kilobytes ? kilobytes * 1024 : undefined;
}

async function collectSigning(
  run: CommandRunner,
  path: string,
): Promise<SystemAppSigning | undefined> {
  const result = await run(
    "codesign",
    ["-dv", "--verbose=2", path],
    COMMAND_TIMEOUT_MS,
  );
  const details = `${result.stdout}\n${result.stderr}`;
  const values: Record<string, string> = {};
  let authority: string | undefined;

  for (const line of details.split(/\r?\n/)) {
    const trimmed = line.trim();
    const index = trimmed.indexOf("=");
    if (index > 0) {
      const key = trimmed.slice(0, index).trim();
      const value = trimmed.slice(index + 1).trim();
      if (!values[key] && value) values[key] = value;
      if (key === "Authority" && !authority) authority = value;
      continue;
    }
    if (!authority && trimmed.startsWith("Authority:")) {
      authority = trimmed.slice("Authority:".length).trim() || undefined;
    }
  }

  const identifier = values.Identifier;
  const teamID = values.TeamIdentifier;
  if (!result.ok && !authority && !identifier && !teamID) return undefined;

  return {
    authority,
    identifier,
    teamID,
    verified: result.ok,
  };
}

// MARK: - Xcode

export async function collectXcodeDetail(
  run: CommandRunner,
  app: SystemApp,
): Promise<SystemXcodeDetail> {
  const developerDir = await resolveDeveloperDir(run, app);
  const environment = developerDir
    ? { ...process.env, DEVELOPER_DIR: developerDir }
    : undefined;

  const [simctl, sdks] = await Promise.all([
    run(
      "xcrun",
      ["simctl", "list", "-j"],
      LONG_COMMAND_TIMEOUT_MS,
      environment,
    ),
    run(
      "xcodebuild",
      ["-showsdks", "-json"],
      LONG_COMMAND_TIMEOUT_MS,
      environment,
    ),
  ]);

  const detail: SystemXcodeDetail = {
    developerDir,
    version: app.version,
    simulators: [],
    sdks: parseXcodeSDKs(parseJSONValue(text(sdks))),
    frameworks: developerDir ? collectFrameworks(developerDir) : [],
  };

  if (!simctl.ok) {
    detail.error = firstLine(text(simctl)) ?? "simctl could not be read.";
    return detail;
  }

  const parsed = parseJSONValue(text(simctl));
  if (!parsed) {
    detail.error = "simctl returned unreadable output.";
    return detail;
  }
  detail.simulators = parseSimctlList(parsed);
  return detail;
}

async function resolveDeveloperDir(
  run: CommandRunner,
  app: SystemApp,
): Promise<string | undefined> {
  const bundled = join(app.path, "Contents", "Developer");
  if (isDirectory(bundled)) return bundled;

  const result = await run("xcode-select", ["-p"], COMMAND_TIMEOUT_MS);
  return firstLine(text(result));
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

/** Parses `xcrun simctl list -j` into runtimes with their devices. */
export function parseSimctlList(value: unknown): SystemSimulatorRuntime[] {
  const record = asRecord(value);
  if (!record) return [];

  const runtimeRecords = new Map<string, SystemSimulatorRuntime>();
  const runtimes = Array.isArray(record.runtimes) ? record.runtimes : [];
  for (const raw of runtimes) {
    const entry = asRecord(raw);
    const identifier = stringValue(entry?.identifier);
    if (!identifier) continue;
    runtimeRecords.set(identifier, {
      identifier,
      name: stringValue(entry?.name) ?? identifier,
      platform: stringValue(entry?.platform) ?? platformFromIdentifier(identifier),
      version: stringValue(entry?.version) ?? versionFromIdentifier(identifier),
      build: stringValue(entry?.buildversion),
      available: entry?.isAvailable !== false,
      devices: [],
    });
  }

  const deviceGroups = asRecord(record.devices) ?? {};
  for (const [runtimeIdentifier, rawDevices] of Object.entries(deviceGroups)) {
    const runtime = ensureRuntime(runtimeRecords, runtimeIdentifier);
    if (!Array.isArray(rawDevices)) continue;
    for (const raw of rawDevices) {
      const entry = asRecord(raw);
      const udid = stringValue(entry?.udid);
      if (!udid) continue;
      const device: SystemSimulatorDevice = {
        udid,
        name: stringValue(entry?.name) ?? udid,
        state: stringValue(entry?.state) ?? "Unknown",
        available: entry?.isAvailable !== false,
        deviceType: stringValue(entry?.deviceTypeIdentifier),
        dataPath: stringValue(entry?.dataPath),
        dataSizeBytes: numberValue(entry?.dataPathSize),
        lastUsedAt: stringValue(entry?.lastUsedAt) ?? stringValue(entry?.lastBootedAt),
      };
      runtime.devices.push(device);
    }
  }

  for (const runtime of runtimeRecords.values()) {
    runtime.devices.sort((left, right) => {
      if (isBooted(left) !== isBooted(right)) return isBooted(left) ? -1 : 1;
      return left.name.localeCompare(right.name);
    });
  }

  return [...runtimeRecords.values()]
    .sort((left, right) => {
      if (left.available !== right.available) return left.available ? -1 : 1;
      const leftBooted = left.devices.some(isBooted);
      const rightBooted = right.devices.some(isBooted);
      if (leftBooted !== rightBooted) return leftBooted ? -1 : 1;
      const platformOrder = platformRank(left.platform) - platformRank(right.platform);
      if (platformOrder !== 0) return platformOrder;
      return right.name.localeCompare(left.name, undefined, { numeric: true });
    });
}

function ensureRuntime(
  runtimes: Map<string, SystemSimulatorRuntime>,
  identifier: string,
): SystemSimulatorRuntime {
  const existing = runtimes.get(identifier);
  if (existing) return existing;
  const runtime: SystemSimulatorRuntime = {
    identifier,
    name: identifier,
    platform: platformFromIdentifier(identifier),
    version: versionFromIdentifier(identifier),
    available: false,
    devices: [],
  };
  runtimes.set(identifier, runtime);
  return runtime;
}

function platformFromIdentifier(identifier: string): string {
  const match = /SimRuntime\.([A-Za-z]+)-/.exec(identifier);
  return match?.[1] ?? "Other";
}

function versionFromIdentifier(identifier: string): string {
  const match = /-(\d+(?:-\d+)*)$/.exec(identifier);
  return match?.[1]?.replace(/-/g, ".") ?? "";
}

function platformRank(platform: string): number {
  const order = ["iOS", "watchOS", "tvOS", "visionOS", "xrOS"];
  const index = order.findIndex((entry) => entry.toLowerCase() === platform.toLowerCase());
  return index === -1 ? order.length : index;
}

function isBooted(device: SystemSimulatorDevice): boolean {
  return device.state.toLowerCase() === "booted";
}

/** Parses `xcodebuild -showsdks -json`, which is a bare array. */
export function parseXcodeSDKs(value: unknown): SystemXcodeSDK[] {
  const entries = Array.isArray(value) ? value : [];
  const sdks: SystemXcodeSDK[] = [];
  const seen = new Set<string>();

  for (const raw of entries) {
    const entry = asRecord(raw);
    const name = stringValue(entry?.displayName);
    if (!name) continue;
    const canonicalName = stringValue(entry?.canonicalName);
    const key = canonicalName ?? name;
    if (seen.has(key)) continue;
    seen.add(key);
    sdks.push({
      name,
      version: stringValue(entry?.productVersion) ?? stringValue(entry?.sdkVersion),
      platform: stringValue(entry?.platform),
      canonicalName,
      path: stringValue(entry?.sdkPath),
    });
  }

  return sdks.sort((left, right) =>
    (left.platform ?? "").localeCompare(right.platform ?? "") ||
    left.name.localeCompare(right.name, undefined, { numeric: true })
  );
}

function collectFrameworks(developerDir: string): SystemXcodeFramework[] {
  const frameworks: SystemXcodeFramework[] = [];
  const seen = new Set<string>();

  const add = (directory: string, platform: string) => {
    for (const entry of listDirectory(directory)) {
      if (!entry.endsWith(".framework")) continue;
      const path = join(directory, entry);
      if (seen.has(path)) continue;
      seen.add(path);
      frameworks.push({ name: basename(entry, ".framework"), path, platform });
    }
  };

  add(join(developerDir, "Library", "Frameworks"), "Xcode");

  const platforms = join(developerDir, "Platforms");
  for (const entry of listDirectory(platforms)) {
    if (!entry.endsWith(".platform")) continue;
    const platform = basename(entry, ".platform");
    add(join(platforms, entry, "Developer", "Library", "Frameworks"), platform);
  }

  return frameworks.sort((left, right) =>
    left.platform.localeCompare(right.platform) || left.name.localeCompare(right.name)
  );
}

// MARK: - Actions

const SIMULATOR_ACTIONS: Record<string, { command: string[]; label: string }> = {
  "simulator.boot": { command: ["simctl", "boot"], label: "boot" },
  "simulator.shutdown": { command: ["simctl", "shutdown"], label: "shut down" },
  "simulator.erase": { command: ["simctl", "erase"], label: "erase" },
  "simulator.delete": { command: ["simctl", "delete"], label: "delete" },
};

const RUNTIME_DELETE_ACTION = "runtime.delete";

/**
 * Runs one management action for an app and returns a fresh detail page. Only
 * the simulator commands above are accepted, and targets must already be part
 * of the hub's current inventory so a request cannot pass arbitrary arguments
 * to simctl.
 */
export async function performAppAction(
  run: CommandRunner,
  detail: SystemAppDetail,
  action: string,
  target: string | undefined,
): Promise<SystemAppDetail> {
  const xcode = detail.xcode;
  if (!xcode) throw new AppActionError("This app has no management actions", 404);

  const developerDir = xcode.developerDir;
  const environment = developerDir
    ? { ...process.env, DEVELOPER_DIR: developerDir }
    : undefined;

  if (action === RUNTIME_DELETE_ACTION) {
    const runtime = target
      ? xcode.simulators.find((entry) => entry.identifier === target)
      : undefined;
    if (!runtime) throw new AppActionError("Unknown simulator runtime", 404);
    await runCommand(run, ["simctl", "runtime", "delete", runtime.identifier], environment, "delete the runtime");
    return collectAppDetail(run, detail.app);
  }

  const spec = SIMULATOR_ACTIONS[action];
  if (!spec) throw new AppActionError("Unknown app action", 400);

  const device = target
    ? xcode.simulators.flatMap((runtime) => runtime.devices).find((entry) => entry.udid === target)
    : undefined;
  if (!device) throw new AppActionError("Unknown simulator", 404);

  if (action === "simulator.erase" && device.state.toLowerCase() === "booted") {
    throw new AppActionError("Shut down the simulator before erasing it", 409);
  }

  await runCommand(run, [...spec.command, device.udid], environment, `${spec.label} the simulator`);
  return collectAppDetail(run, detail.app);
}

async function runCommand(
  run: CommandRunner,
  args: string[],
  environment: NodeJS.ProcessEnv | undefined,
  description: string,
): Promise<void> {
  const result = await run("xcrun", args, LONG_COMMAND_TIMEOUT_MS, environment);
  if (result.ok) return;
  const message = firstLine(text(result)) ?? `Could not ${description}.`;
  throw new AppActionError(message, 409);
}

function firstLine(value: string): string | undefined {
  return lines(value)[0];
}

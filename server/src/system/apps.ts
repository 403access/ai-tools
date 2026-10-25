import { basename, join } from "node:path";
import { homedir, platform } from "node:os";
import type { SystemApp } from "../types.ts";
import { hasAppIcon } from "./appIcons.ts";
import { APP_DIRECTORIES, LONG_COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import {
  asRecord,
  lines,
  listDirectory,
  parseJSON,
  parseJSONValue,
  readFileSafe,
  stringValue,
  text,
} from "./util.ts";

export async function collectApps(run: CommandRunner): Promise<SystemApp[]> {
  const os = platform();
  try {
    if (os === "darwin") return await collectMacApps(run);
    if (os === "linux") return collectLinuxApps();
    if (os === "win32") return await collectWindowsApps(run);
  } catch {
    // Fall through to an empty list; the endpoint still returns everything else.
  }
  return [];
}

async function collectMacApps(run: CommandRunner): Promise<SystemApp[]> {
  const result = await run(
    "system_profiler",
    ["SPApplicationsDataType", "-json", "-detailLevel", "mini"],
    LONG_COMMAND_TIMEOUT_MS,
  );
  const entries = parseJSON(text(result))?.SPApplicationsDataType;
  if (!Array.isArray(entries)) return scanAppDirectories();

  const apps: SystemApp[] = [];
  for (const raw of entries) {
    const entry = asRecord(raw);
    if (!entry) continue;
    const path = stringValue(entry.path);
    const name = stringValue(entry._name) ?? (path ? basename(path, ".app") : undefined);
    if (!name || !path) continue;
    apps.push({
      name,
      path,
      version: stringValue(entry.version),
      bundleID: stringValue(entry.bundleid),
      source: stringValue(entry.obtained_from),
      architecture: stringValue(entry.arch_kind),
      lastModified: stringValue(entry.lastModified),
      hasIcon: hasAppIcon(path),
    });
  }
  apps.sort((a, b) => a.name.localeCompare(b.name));
  return apps;
}

function scanAppDirectories(): SystemApp[] {
  const apps: SystemApp[] = [];
  const seen = new Set<string>();
  for (const directory of APP_DIRECTORIES) {
    const paths = listDirectory(directory);
    for (const entry of paths) {
      if (!entry.endsWith(".app")) continue;
      const path = join(directory, entry);
      if (seen.has(path)) continue;
      seen.add(path);
      apps.push({ name: basename(entry, ".app"), path, hasIcon: hasAppIcon(path) });
    }
  }
  apps.sort((a, b) => a.name.localeCompare(b.name));
  return apps;
}

function collectLinuxApps(): SystemApp[] {
  const directories = [
    "/usr/share/applications",
    "/usr/local/share/applications",
    join(homedir(), ".local", "share", "applications"),
    "/var/lib/flatpak/exports/share/applications",
    join(homedir(), ".local", "share", "flatpak", "exports", "share", "applications"),
    "/var/lib/snapd/desktop/applications",
  ];
  const apps: SystemApp[] = [];
  const seen = new Set<string>();

  for (const directory of directories) {
    for (const entry of listDirectory(directory)) {
      if (!entry.endsWith(".desktop")) continue;
      const path = join(directory, entry);
      const values = parseDesktopEntry(readFileSafe(path));
      const name = values.Name;
      if (!name || seen.has(name)) continue;
      seen.add(name);
      apps.push({
        name,
        path,
        version: values.Version,
        bundleID: values.StartupWMClass,
        source: values.Exec ? "desktop entry" : undefined,
        hasIcon: hasAppIcon(path),
      });
    }
  }
  apps.sort((a, b) => a.name.localeCompare(b.name));
  return apps;
}

async function collectWindowsApps(run: CommandRunner): Promise<SystemApp[]> {
  const result = await run(
    "powershell",
    [
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      "$paths=@('HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'); Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,InstallLocation,Publisher | ConvertTo-Json -Compress",
    ],
    LONG_COMMAND_TIMEOUT_MS,
  );
  const raw = parseJSONValue(text(result));
  const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
  const apps: SystemApp[] = [];
  for (const rawEntry of entries) {
    const entry = asRecord(rawEntry);
    const name = stringValue(entry?.DisplayName);
    if (!name) continue;
    apps.push({
      name,
      path: stringValue(entry?.InstallLocation) ?? "",
      version: stringValue(entry?.DisplayVersion),
      source: stringValue(entry?.Publisher),
    });
  }
  apps.sort((a, b) => a.name.localeCompare(b.name));
  return apps;
}

export function parseDesktopEntry(value: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of lines(value)) {
    if (line.startsWith("#") || line.startsWith("[")) continue;
    const index = line.indexOf("=");
    if (index <= 0) continue;
    result[line.slice(0, index).trim()] = line.slice(index + 1).trim();
  }
  return result;
}

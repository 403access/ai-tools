import { platform } from "node:os";
import type { SystemDisk } from "../types.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { asRecord, numberValue, parseJSONValue, stringValue, text } from "./util.ts";

export async function collectDisks(run: CommandRunner): Promise<SystemDisk[]> {
  const os = platform();
  if (os === "win32") {
    const result = await run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID,FileSystem,Size,FreeSpace,DriveType | ConvertTo-Json -Compress",
      ],
      COMMAND_TIMEOUT_MS,
    );
    const raw = parseJSONValue(text(result));
    const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
    return entries.flatMap((rawEntry) => {
      const entry = asRecord(rawEntry);
      const mount = stringValue(entry?.DeviceID);
      const total = numberValue(entry?.Size);
      const free = numberValue(entry?.FreeSpace);
      if (!mount || total === undefined || free === undefined) return [];
      return [{
        mount,
        filesystem: stringValue(entry?.FileSystem) ?? "unknown",
        type: winDriveType(numberValue(entry?.DriveType)),
        totalBytes: total,
        usedBytes: Math.max(0, total - free),
        freeBytes: free,
      }];
    });
  }

  const result = await run("df", ["-kP"], COMMAND_TIMEOUT_MS);
  if (!result.ok) return [];
  const disks = parseDF(text(result));
  return disks.sort((a, b) => {
    if (a.mount === "/") return -1;
    if (b.mount === "/") return 1;
    return a.mount.localeCompare(b.mount);
  });
}

export function parseDF(value: string): SystemDisk[] {
  const disks: SystemDisk[] = [];
  for (const line of value.split(/\r?\n/).slice(1)) {
    const match = line.match(/^(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(.+)$/);
    if (!match) continue;
    const filesystem = match[1] ?? "";
    const totalKiB = Number.parseInt(match[2] ?? "", 10);
    const usedKiB = Number.parseInt(match[3] ?? "", 10);
    const freeKiB = Number.parseInt(match[4] ?? "", 10);
    const mount = (match[6] ?? "").trim();
    if (!mount || !Number.isFinite(totalKiB) || totalKiB === 0) continue;
    if (/^(devfs|map|none|udev|tmpfs|overlay)$/i.test(filesystem) && mount !== "/") continue;
    if (filesystem === "devfs") continue;
    disks.push({
      mount,
      filesystem,
      totalBytes: totalKiB * 1_024,
      usedBytes: usedKiB * 1_024,
      freeBytes: freeKiB * 1_024,
      readOnly: false,
      removable: mount.startsWith("/Volumes/") || mount.startsWith("/media/") || mount.startsWith("/run/media/"),
    });
  }
  return disks;
}

export function winDriveType(value: number | undefined): string | undefined {
  switch (value) {
    case 2: return "removable";
    case 3: return "fixed";
    case 4: return "network";
    case 5: return "optical";
    case 6: return "ram";
    default: return undefined;
  }
}

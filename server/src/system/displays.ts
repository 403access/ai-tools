import { platform } from "node:os";
import type { SystemDisplayGroup } from "../types.ts";
import { COMMAND_TIMEOUT_MS, LONG_COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { asRecord, numberValue, parseJSON, parseJSONValue, stringValue, text } from "./util.ts";

export async function collectDisplays(run: CommandRunner): Promise<SystemDisplayGroup[]> {
  const os = platform();
  if (os === "darwin") {
    const result = await run(
      "system_profiler",
      ["SPDisplaysDataType", "-json", "-detailLevel", "mini"],
      LONG_COMMAND_TIMEOUT_MS,
    );
    const entries = parseJSON(text(result))?.SPDisplaysDataType;
    if (!Array.isArray(entries)) return [];
    const groups: SystemDisplayGroup[] = [];
    for (const raw of entries) {
      const entry = asRecord(raw);
      if (!entry) continue;
      const displaysRaw = entry.spdisplays_ndrvs;
      const displays = Array.isArray(displaysRaw)
        ? displaysRaw.flatMap((displayRaw) => {
            const display = asRecord(displayRaw);
            if (!display) return [];
            const name = stringValue(display._name) ?? "Display";
            return [{
              name,
              resolution: stringValue(display["_spdisplays_resolution"]) ?? stringValue(display.spdisplays_resolution),
              pixels: stringValue(display["_spdisplays_pixels"]) ?? stringValue(display.spdisplays_pixels),
              type: stringValue(display.spdisplays_connection_type)?.replace(/^spdisplays_/, ""),
              main: stringValue(display.spdisplays_main) === "spdisplays_yes",
              online: stringValue(display.spdisplays_online) !== "spdisplays_no",
              mirror: stringValue(display.spdisplays_mirror) === "spdisplays_on",
            }];
          })
        : [];
      groups.push({
        name: stringValue(entry._name) ?? "GPU",
        vendor: stringValue(entry.spdisplays_vendor)?.replace(/^sppci_vendor_/, ""),
        model: stringValue(entry.sppci_model),
        cores: numberValue(entry.sppci_cores),
        displays,
      });
    }
    return groups;
  }

  if (os === "linux") {
    const result = await run("xrandr", ["--query"], COMMAND_TIMEOUT_MS);
    if (!result.ok) return [];
    const displays = text(result)
      .split("\n")
      .flatMap((line) => {
        const match = line.match(/^(\S+)\s+connected(?:\s+primary)?\s+(\d+)x(\d+)/);
        if (!match) return [];
        return [{
          name: match[1] ?? "Display",
          resolution: `${match[2]} x ${match[3]}`,
          main: line.includes(" connected primary "),
          online: true,
        }];
      });
    return displays.length > 0 ? [{ name: "Displays", displays }] : [];
  }

  if (os === "win32") {
    const result = await run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution,AdapterRAM | ConvertTo-Json -Compress",
      ],
      COMMAND_TIMEOUT_MS,
    );
    const raw = parseJSONValue(text(result));
    const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
    return entries.flatMap((rawEntry) => {
      const entry = asRecord(rawEntry);
      const name = stringValue(entry?.Name);
      if (!name) return [];
      const width = numberValue(entry?.CurrentHorizontalResolution);
      const height = numberValue(entry?.CurrentVerticalResolution);
      return [{
        name,
        model: name,
        displays: [{
          name,
          resolution: width && height ? `${width} x ${height}` : undefined,
          online: true,
        }],
      }];
    });
  }

  return [];
}


import { platform } from "node:os";
import { join } from "node:path";
import type { SystemBattery } from "../types.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { firstLine, listDirectory, numberValue, parseJSONRecord, readFileSafe, round, text } from "./util.ts";

export async function collectBattery(run: CommandRunner): Promise<SystemBattery | null> {
  const os = platform();
  if (os === "darwin") {
    const [pmset, ioreg] = await Promise.all([
      run("pmset", ["-g", "batt"], COMMAND_TIMEOUT_MS),
      run("ioreg", ["-r", "-c", "AppleSmartBattery", "-w0"], COMMAND_TIMEOUT_MS),
    ]);
    const info = parsePMSetBattery(text(pmset));
    if (!info) return null;
    const details = parseIORegBattery(text(ioreg));
    return {
      present: true,
      ...info,
      cycleCount: details.cycleCount,
      condition: details.condition,
      temperatureC: details.temperatureC,
      healthPercent: details.maxCapacity && details.designCapacity
        ? round((details.maxCapacity / details.designCapacity) * 100, 0)
        : undefined,
    };
  }

  if (os === "linux") {
    const base = "/sys/class/power_supply";
    for (const entry of listDirectory(base)) {
      if (!/^BAT/i.test(entry)) continue;
      const directory = join(base, entry);
      const percent = numberValue(readFileSafe(join(directory, "capacity")).trim());
      const status = readFileSafe(join(directory, "status")).trim();
      const energyNow = numberValue(readFileSafe(join(directory, "energy_now")).trim());
      const energyFull = numberValue(readFileSafe(join(directory, "energy_full")).trim());
      const design = numberValue(readFileSafe(join(directory, "energy_full_design")).trim());
      const powerNow = numberValue(readFileSafe(join(directory, "power_now")).trim());
      let minutesRemaining: number | undefined;
      if (energyNow !== undefined && powerNow && powerNow > 0) {
        minutesRemaining = Math.round((energyNow / powerNow) * 60);
      }
      return {
        present: true,
        percent,
        charging: /charging/i.test(status) && !/discharging/i.test(status),
        state: status || undefined,
        minutesRemaining,
        healthPercent: energyFull && design ? round((energyFull / design) * 100, 0) : undefined,
      };
    }
    return null;
  }

  if (os === "win32") {
    const result = await run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-CimInstance Win32_Battery | Select-Object -First 1 EstimatedChargeRemaining,BatteryStatus,DesignCapacity,FullChargeCapacity | ConvertTo-Json -Compress",
      ],
      COMMAND_TIMEOUT_MS,
    );
    const entry = parseJSONRecord(firstLine(text(result)));
    if (!entry) return null;
    const percent = numberValue(entry.EstimatedChargeRemaining);
    const status = numberValue(entry.BatteryStatus);
    return {
      present: true,
      percent,
      charging: status === 2,
      state: winBatteryState(status),
      healthPercent: numberValue(entry.FullChargeCapacity) && numberValue(entry.DesignCapacity)
        ? round((numberValue(entry.FullChargeCapacity)! / numberValue(entry.DesignCapacity)!) * 100, 0)
        : undefined,
    };
  }

  return null;
}

export function parsePMSetBattery(value: string): Partial<SystemBattery> | null {
  const line = value.split(/\r?\n/).find((entry) => /InternalBattery|Battery/.test(entry) && /%/.test(entry));
  if (!line) return null;
  const percent = Number.parseInt(/(\d+)%/.exec(line)?.[1] ?? "", 10);
  const state = /;\s*([^;]+);/.exec(line)?.[1]?.trim();
  const remaining = /(\d+):(\d+)\s+remaining/.exec(line);
  const minutesRemaining = remaining
    ? Number.parseInt(remaining[1] ?? "0", 10) * 60 + Number.parseInt(remaining[2] ?? "0", 10)
    : undefined;
  return {
    percent: Number.isFinite(percent) ? percent : undefined,
    charging: /\bcharging\b|charged|AC Power/i.test(line),
    state,
    minutesRemaining,
  };
}

export function parseIORegBattery(value: string): {
  maxCapacity?: number;
  designCapacity?: number;
  cycleCount?: number;
  condition?: string;
  temperatureC?: number;
} {
  const read = (key: string): number | undefined => {
    const match = new RegExp(`"${key}"\\s*=\\s*(\\d+)`).exec(value);
    const parsed = Number.parseInt(match?.[1] ?? "", 10);
    return Number.isFinite(parsed) ? parsed : undefined;
  };
  const health = /"BatteryHealth"\s*=\s*"([^"]+)"/.exec(value)?.[1];
  // `MaxCapacity` on modern Macs is a percentage; the raw mAh value lives in
  // AppleRawMaxCapacity or in the nested BatteryData dictionary.
  const capacity = read("AppleRawMaxCapacity") ?? read("FullChargeCapacity");
  const design = read("DesignCapacity");
  const temperature = read("Temperature");
  const permanentFailure = read("PermanentFailureStatus");
  return {
    maxCapacity: capacity,
    designCapacity: design,
    cycleCount: read("CycleCount"),
    condition: health ?? (permanentFailure === 0 ? "Good" : undefined),
    temperatureC: temperature ? round(temperature / 10 - 273.15, 1) : undefined,
  };
}

export function winBatteryState(value: number | undefined): string | undefined {
  switch (value) {
    case 1: return "discharging";
    case 2: return "on AC";
    case 3: return "fully charged";
    case 4: return "low";
    case 5: return "critical";
    case 6: return "charging";
    case 7: return "charging, high";
    case 8: return "charging, low";
    case 9: return "charging, critical";
    case 11: return "partially charged";
    default: return undefined;
  }
}

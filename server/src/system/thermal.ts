import { platform } from "node:os";
import { join } from "node:path";
import type { SystemThermal } from "../types.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { lines, listDirectory, numberValue, readFileSafe, round, text } from "./util.ts";

export async function collectThermal(run: CommandRunner): Promise<SystemThermal | null> {
  const os = platform();
  if (os === "darwin") {
    const result = await run("pmset", ["-g", "therm"], COMMAND_TIMEOUT_MS);
    if (!result.ok) return null;
    const values = parseColonNumberLines(text(result));
    const speedLimit = values.CPU_Speed_Limit;
    const schedulerLimit = values.CPU_Scheduler_Limit;
    if (speedLimit === undefined && schedulerLimit === undefined) return null;
    const pressure = speedLimit !== undefined
      ? speedLimit >= 100 ? "Nominal" : speedLimit >= 80 ? "Fair" : speedLimit >= 50 ? "Serious" : "Critical"
      : undefined;
    return {
      cpuSpeedLimitPercent: speedLimit,
      cpuSchedulerLimitPercent: schedulerLimit,
      pressure,
    };
  }

  if (os === "linux") {
    const base = "/sys/class/thermal";
    const sensors: Array<{ name: string; temperatureC: number }> = [];
    for (const entry of listDirectory(base)) {
      if (!entry.startsWith("thermal_zone")) continue;
      const directory = join(base, entry);
      const raw = numberValue(readFileSafe(join(directory, "temp")).trim());
      if (raw === undefined) continue;
      sensors.push({
        name: readFileSafe(join(directory, "type")).trim() || entry,
        temperatureC: round(raw / 1_000, 1),
      });
    }
    if (sensors.length === 0) return null;
    const hottest = sensors.reduce((max, sensor) => sensor.temperatureC > max ? sensor.temperatureC : max, 0);
    return {
      temperatureC: hottest,
      sensors,
      pressure: hottest >= 95 ? "Critical" : hottest >= 85 ? "Serious" : hottest >= 70 ? "Fair" : "Nominal",
    };
  }

  return null;
}

export function parseColonNumberLines(value: string): Record<string, number> {
  const result: Record<string, number> = {};
  for (const line of lines(value)) {
    const match = line.match(/^([A-Za-z0-9_]+)\s*=\s*(\d+)/);
    if (!match?.[1] || !match[2]) continue;
    result[match[1]] = Number.parseInt(match[2], 10);
  }
  return result;
}

import { platform } from "node:os";
import type { SystemAudio } from "../types.ts";
import { findExecutable } from "./commands.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { numberValue, text } from "./util.ts";

export async function collectAudio(run: CommandRunner): Promise<SystemAudio | null> {
  const os = platform();
  if (os === "darwin") {
    const result = await run("osascript", ["-e", "get volume settings"], COMMAND_TIMEOUT_MS);
    const textValue = text(result);
    const volume = numberValue(/output volume:(\d+)/.exec(textValue)?.[1]);
    const muted = /output muted:(true|false)/i.exec(textValue)?.[1];
    if (volume === undefined) return null;
    return {
      volumePercent: volume,
      muted: muted?.toLowerCase() === "true",
      controllable: true,
    };
  }

  if (os === "linux") {
    const pactl = findExecutable("pactl");
    if (!pactl) return null;
    const [volumeResult, muteResult] = await Promise.all([
      run(pactl, ["get-sink-volume", "@DEFAULT_SINK@"], COMMAND_TIMEOUT_MS),
      run(pactl, ["get-sink-mute", "@DEFAULT_SINK@"], COMMAND_TIMEOUT_MS),
    ]);
    const volume = numberValue(/(\d+)%/.exec(text(volumeResult))?.[1]);
    const muted = /\bMute:\s*(yes|no)/i.exec(text(muteResult))?.[1];
    if (volume === undefined) return null;
    return {
      volumePercent: Math.min(100, volume),
      muted: muted?.toLowerCase() === "yes",
      controllable: true,
    };
  }

  return null;
}

export async function setSystemVolume(run: CommandRunner, percent: number): Promise<void> {
  const os = platform();
  if (os === "darwin") {
    await run("osascript", ["-e", `set volume output volume ${percent}`], COMMAND_TIMEOUT_MS);
    return;
  }
  if (os === "linux") {
    const pactl = findExecutable("pactl");
    if (pactl) {
      await run(pactl, ["set-sink-volume", "@DEFAULT_SINK@", `${percent}%`], COMMAND_TIMEOUT_MS);
    }
  }
}

export async function setSystemMuted(run: CommandRunner, muted: boolean): Promise<void> {
  const os = platform();
  if (os === "darwin") {
    await run(
      "osascript",
      ["-e", `set volume output muted ${muted ? "true" : "false"}`],
      COMMAND_TIMEOUT_MS,
    );
    return;
  }
  if (os === "linux") {
    const pactl = findExecutable("pactl");
    if (pactl) {
      await run(
        pactl,
        ["set-sink-mute", "@DEFAULT_SINK@", muted ? "1" : "0"],
        COMMAND_TIMEOUT_MS,
      );
    }
  }
}

/** Older macOS versions without MediaRemote still expose the big players. */

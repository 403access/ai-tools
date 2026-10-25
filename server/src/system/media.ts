import { platform } from "node:os";
import type { SystemMedia } from "../types.ts";
import { findExecutable } from "./commands.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import {
  asRecord,
  firstLine,
  lines,
  numberValue,
  parseJSONRecord,
  round,
  stringValue,
  text,
} from "./util.ts";

export class MediaControlError extends Error {
  readonly status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.name = "MediaControlError";
    this.status = status;
  }
}

const MEDIA_COMMANDS: Record<string, number> = {
  toggle: 2,
  play: 0,
  pause: 1,
  stop: 3,
  next: 4,
  previous: 5,
  back15: 12,
  forward15: 13,
};

const NOW_PLAYING_SCRIPT = String.raw`function run() {
  try {
    const bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
    bundle.load;
    const Request = $.NSClassFromString('MRNowPlayingRequest');
    if (!Request) return JSON.stringify({ error: 'MediaRemote unavailable' });
    const path = Request.localNowPlayingPlayerPath;
    const info = Request.localNowPlayingItem.nowPlayingInfo;
    const read = (key) => {
      if (!info) return null;
      const value = info.valueForKey(key);
      if (!value) return null;
      const converted = value.js;
      return converted === undefined ? null : converted;
    };
    const appName = path && path.client && path.client.displayName ? path.client.displayName.js : null;
    const bundleID = path && path.client && path.client.bundleIdentifier ? path.client.bundleIdentifier.js : null;
    const title = read('kMRMediaRemoteNowPlayingInfoTitle');
    if (!appName && !title) return JSON.stringify({ media: [] });
    const rate = read('kMRMediaRemoteNowPlayingInfoPlaybackRate');
    const supported = [];
    const commands = Request.localSupportedCommands;
    if (commands) {
      for (let index = 0; index < commands.count; index += 1) {
        try {
          const info = commands.objectAtIndex(index);
          const command = info.command;
          if (command) supported.push(command.js);
        } catch (_) {}
      }
    }
    return JSON.stringify({ media: [{
      app: appName || 'Unknown app',
      bundleID: bundleID || null,
      title: title || null,
      artist: read('kMRMediaRemoteNowPlayingInfoArtist') || null,
      album: read('kMRMediaRemoteNowPlayingInfoAlbum') || null,
      elapsedSeconds: read('kMRMediaRemoteNowPlayingInfoElapsedTime'),
      durationSeconds: read('kMRMediaRemoteNowPlayingInfoDuration'),
      playbackRate: rate,
      state: rate === 0 ? 'paused' : 'playing',
      source: 'mediaremote',
      supportedCommands: supported
    }] });
  } catch (error) {
    return JSON.stringify({ error: String(error) });
  }
}`;

/**
 * Sends one MediaRemote command to the current player. The integer is passed as
 * the first osascript argument by the hub.
 */
const MEDIA_CONTROL_SCRIPT = String.raw`function run(argv) {
  try {
    const command = parseInt(argv[0] || '-1', 10);
    if (!Number.isFinite(command) || command < 0) return JSON.stringify({ ok: false, error: 'Invalid command' });
    const bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
    bundle.load;
    const Request = $.NSClassFromString('MRNowPlayingRequest');
    if (!Request) return JSON.stringify({ ok: false, error: 'MediaRemote unavailable' });
    const path = Request.localNowPlayingPlayerPath;
    if (!path) return JSON.stringify({ ok: false, error: 'Nothing is playing' });
    const request = Request.alloc.initWithPlayerPath(path);
    request.sendCommandOptionsQueueCompletion(command, $.NSDictionary.dictionary, $.NSOperationQueue.mainQueue, null);
    return JSON.stringify({ ok: true });
  } catch (error) {
    return JSON.stringify({ ok: false, error: String(error) });
  }
}`;

const APPLESCRIPT_MEDIA_SCRIPT = String.raw`set output to ""
if application "Music" is running then
  tell application "Music"
    if player state is not stopped then
      set output to output & "Music" & tab & (player state as text) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & (duration of current track as text) & linefeed
    end if
  end tell
end if
if application "Spotify" is running then
  tell application "Spotify"
    if player state is not stopped then
      set output to output & "Spotify" & tab & (player state as text) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & (duration of current track as text) & linefeed
    end if
  end tell
end if
return output`;


export async function collectMedia(run: CommandRunner): Promise<SystemMedia[]> {
  const os = platform();
  let media: SystemMedia[] = [];

  if (os === "darwin") {
    const result = await run(
      "osascript",
      ["-l", "JavaScript", "-e", NOW_PLAYING_SCRIPT],
      COMMAND_TIMEOUT_MS,
    );
    const payload = parseJSONRecord(firstLine(text(result)));
    const entries = payload?.media;
    if (Array.isArray(entries)) {
      media = entries.flatMap((raw) => normalizeMedia(raw));
    }
    if (media.length === 0) {
      media = await collectAppleScriptMedia(run);
    }
    media = mergeMedia(media, await collectMediaAssertions(run));
    return media.sort(mediaSort);
  }

  if (os === "linux") {
    const playerctl = findExecutable("playerctl");
    if (!playerctl) return [];
    const listed = await run(playerctl, ["-l"], COMMAND_TIMEOUT_MS);
    const players = lines(text(listed));
    const format = "{{playerName}}\t{{status}}\t{{title}}\t{{artist}}\t{{album}}\t{{position}}\t{{mpris:length}}";
    const results = await Promise.all(
      players.map(async (player) => {
        const result = await run(
          playerctl,
          ["--player", player, "metadata", "--format", format],
          COMMAND_TIMEOUT_MS,
        );
        return parsePlayerctlMedia(text(result));
      }),
    );
    return results.flat().sort(mediaSort);
  }

  return [];
}

export async function controlAppleScriptMedia(run: CommandRunner, action: string): Promise<boolean> {
  const verb = action === "toggle"
    ? "playpause"
    : action === "play"
      ? "play"
      : action === "pause"
        ? "pause"
        : action === "next"
          ? "next track"
          : action === "previous"
            ? "previous track"
            : action === "stop"
              ? "stop"
              : null;
  if (!verb) return false;

  const script = String.raw`set did to false
if application "Music" is running then
tell application "Music"
  if player state is not stopped then
    ${verb}
    set did to true
  end if
end tell
end if
if not did and application "Spotify" is running then
tell application "Spotify"
  if player state is not stopped then
    ${verb}
    set did to true
  end if
end tell
end if
return did`;
  const result = await run("osascript", ["-e", script], COMMAND_TIMEOUT_MS);
  return /true/i.test(firstLine(text(result)) ?? "");
}


export async function collectAppleScriptMedia(run: CommandRunner): Promise<SystemMedia[]> {
  const result = await run("osascript", ["-e", APPLESCRIPT_MEDIA_SCRIPT], COMMAND_TIMEOUT_MS);
  const media: SystemMedia[] = [];
  for (const line of lines(text(result))) {
    const [app, state, title, artist, album, position, duration] = line.split("\t");
    if (!app) continue;
    const isSpotify = app.trim().toLowerCase() === "spotify";
    const elapsed = numberValue(position);
    const total = numberValue(duration);
    media.push({
      app: app.trim(),
      title: title?.trim() || undefined,
      artist: artist?.trim() || undefined,
      album: album?.trim() || undefined,
      state: state?.toLowerCase().includes("play") ? "playing" : "paused",
      elapsedSeconds: elapsed,
      durationSeconds: total === undefined ? undefined : isSpotify ? total / 1_000 : total,
      source: "applescript",
      supportedCommands: [0, 1, 2, 4, 5],
    });
  }
  return media;
}

/**
 * `pmset` lists media assertions for browsers and video apps that do not
 * publish a MediaRemote item. It tells us the owning app and whether audio or
 * video is active, even without track metadata.
 */
export async function collectMediaAssertions(run: CommandRunner): Promise<SystemMedia[]> {
  const result = await run("pmset", ["-g", "assertions"], COMMAND_TIMEOUT_MS);
  if (!result.ok) return [];
  const byApp = new Map<string, SystemMedia>();
  for (const line of text(result).split(/\r?\n/)) {
    const match = line.match(/pid\s+\d+\(([^)]+)\):.*?(Playing audio|Video Wake Lock)/);
    if (!match?.[1]) continue;
    const app = match[1].trim();
    if (!app) continue;
    const key = app.toLowerCase();
    const kind = /video wake lock/i.test(match[2] ?? "") ? "video" : "audio";
    const existing = byApp.get(key);
    if (existing) {
      // An app can hold both audio and video assertions; video is the more
      // useful label for a browser or player.
      if (kind === "video") existing.kind = "video";
      continue;
    }
    byApp.set(key, {
      app,
      state: "playing",
      kind,
      source: "assertion",
    });
  }
  return [...byApp.values()];
}

export async function controlPlayback(run: CommandRunner, action: string): Promise<boolean> {
  const command = MEDIA_COMMANDS[action];
  if (command === undefined) {
    throw new MediaControlError(`Unknown media action: ${action}`, 400);
  }

  const os = platform();
  if (os === "darwin") {
    const result = await run(
      "osascript",
      ["-l", "JavaScript", "-e", MEDIA_CONTROL_SCRIPT, String(command)],
      COMMAND_TIMEOUT_MS,
    );
    const payload = parseJSONRecord(firstLine(text(result)));
    if (payload?.ok === true) return true;
    return controlAppleScriptMedia(run, action);
  }

  if (os === "linux") {
    const playerctl = findExecutable("playerctl");
    if (!playerctl) return false;
    const commandName = action === "toggle"
      ? "play-pause"
      : action === "back15"
        ? "previous"
        : action === "forward15"
          ? "next"
          : action;
    const result = await run(playerctl, [commandName], COMMAND_TIMEOUT_MS);
    return result.ok;
  }

  return false;
}

function normalizeMedia(raw: unknown): SystemMedia[] {
  const entry = asRecord(raw);
  const app = stringValue(entry?.app);
  if (!app) return [];

  const stateValue = stringValue(entry?.state)?.toLowerCase();
  const state = stateValue === "playing" || stateValue === "paused" || stateValue === "stopped"
    ? stateValue
    : undefined;
  const playbackRate = numberValue(entry?.playbackRate);
  const kindValue = stringValue(entry?.kind)?.toLowerCase();
  const kind = kindValue === "audio" || kindValue === "video" ? kindValue : undefined;
  const commands = Array.isArray(entry?.supportedCommands)
    ? entry.supportedCommands
        .map((command) => numberValue(command))
        .filter((command): command is number => command !== undefined)
    : [];
  // Some players briefly report no command list while still accepting the
  // basic transport commands MediaRemote exposes.
  if (commands.length === 0) commands.push(0, 1, 2);

  return [{
    app,
    bundleID: stringValue(entry?.bundleID),
    title: stringValue(entry?.title),
    artist: stringValue(entry?.artist),
    album: stringValue(entry?.album),
    state: state ?? (playbackRate === 0 ? "paused" : playbackRate === undefined ? undefined : "playing"),
    elapsedSeconds: numberValue(entry?.elapsedSeconds),
    durationSeconds: numberValue(entry?.durationSeconds),
    playbackRate,
    kind,
    source: "mediaremote",
    supportedCommands: commands,
  }];
}

function parsePlayerctlMedia(value: string): SystemMedia[] {
  const [app, status, title, artist, album, position, length] = value.split("\t");
  if (!app?.trim() || /^stopped$/i.test(status?.trim() ?? "")) return [];
  const positionMicros = numberValue(position);
  const lengthMicros = numberValue(length);
  return [{
    app: app.trim(),
    title: title?.trim() || undefined,
    artist: artist?.trim() || undefined,
    album: album?.trim() || undefined,
    state: /^playing$/i.test(status?.trim() ?? "") ? "playing" : "paused",
    elapsedSeconds: positionMicros === undefined ? undefined : round(positionMicros / 1_000_000, 1),
    durationSeconds: lengthMicros === undefined ? undefined : round(lengthMicros / 1_000_000, 1),
    source: "playerctl",
    supportedCommands: [0, 1, 2, 4, 5],
  }];
}

function mergeMedia(primary: SystemMedia[], extra: SystemMedia[]): SystemMedia[] {
  const byApp = new Map<string, SystemMedia>();
  for (const item of [...primary, ...extra]) {
    const key = item.app.trim().toLowerCase();
    if (!key) continue;
    const existing = byApp.get(key);
    if (!existing) {
      byApp.set(key, item);
      continue;
    }
    existing.state = item.state === "playing" ? "playing" : item.state ?? existing.state;
    existing.kind = existing.kind ?? item.kind;
    if (!existing.title && item.title) existing.title = item.title;
    if (!existing.artist && item.artist) existing.artist = item.artist;
    if (!existing.album && item.album) existing.album = item.album;
  }
  return [...byApp.values()];
}

function mediaSort(left: SystemMedia, right: SystemMedia): number {
  const rank = (value: SystemMedia): number => value.state === "playing" ? 0 : value.state === "paused" ? 1 : 2;
  const difference = rank(left) - rank(right);
  if (difference !== 0) return difference;
  return left.app.localeCompare(right.app);
}

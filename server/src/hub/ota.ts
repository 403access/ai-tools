import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { dirname, join } from "node:path";
import type { OtaArtifact } from "../types.ts";

/** Build ids are directory names, so keep them strictly URL- and path-safe. */
const ID_PATTERN = /^[a-z0-9][a-z0-9-]{5,63}$/;

/** The OTA builds live next to the hub database, like the rest of its state. */
export function otaRootFor(dbPath: string): string {
  return join(dirname(dbPath), "ota");
}

function readArtifact(root: string, id: string): OtaArtifact | null {
  if (!ID_PATTERN.test(id)) return null;
  const metaPath = join(root, id, "meta.json");
  if (!existsSync(metaPath)) return null;
  try {
    const value = JSON.parse(readFileSync(metaPath, "utf8")) as Record<string, unknown>;
    const text = (key: string): string =>
      typeof value[key] === "string" ? (value[key] as string) : "";
    const createdAt = typeof value.createdAt === "number" ? value.createdAt : 0;
    return {
      id,
      title: text("title") || "OpenCodeBar",
      bundleId: text("bundleId"),
      version: text("version"),
      build: text("build"),
      commitSha: text("commitSha"),
      branch: text("branch"),
      worktree: text("worktree"),
      createdAt,
    };
  } catch {
    // A partially written or hand-edited build should not break the list.
    return null;
  }
}

/** Reads the published builds from disk. The list is small, so no cache. */
export class OtaStore {
  constructor(readonly root: string) {}

  list(): OtaArtifact[] {
    let entries: string[] = [];
    try {
      entries = readdirSync(this.root, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => entry.name);
    } catch {
      return [];
    }
    return entries
      .map((id) => readArtifact(this.root, id))
      .filter((artifact): artifact is OtaArtifact => artifact !== null)
      .sort((a, b) => b.createdAt - a.createdAt);
  }

  latest(): OtaArtifact | null {
    return this.list()[0] ?? null;
  }

  get(id: string): OtaArtifact | null {
    return readArtifact(this.root, id);
  }

  /** Absolute path to the IPA, or null when the build has no payload. */
  ipaPath(id: string): string | null {
    if (!ID_PATTERN.test(id)) return null;
    const path = join(this.root, id, "app.ipa");
    try {
      return statSync(path).size > 0 ? path : null;
    } catch {
      return null;
    }
  }

  /** Keeps the newest builds so an old IPA cannot fill the data directory. */
  prune(keep = 5): void {
    for (const artifact of this.list().slice(keep)) {
      rmSync(join(this.root, artifact.id), { recursive: true, force: true });
    }
  }

  /** Creates the root before a build writes into it. */
  prepare(): void {
    mkdirSync(this.root, { recursive: true, mode: 0o700 });
  }
}

/** The origin the phone used to reach the hub, honouring the tunnel proxy. */
export function requestOrigin(request: Request): string {
  const url = new URL(request.url);
  const forwarded = request.headers.get("x-forwarded-proto")?.split(",")[0]?.trim();
  const protocol =
    forwarded === "https" || forwarded === "http"
      ? forwarded
      : url.protocol.replace(":", "");
  const host = request.headers.get("host")?.trim() || url.host;
  return `${protocol}://${host}`;
}

export function otaManifest(artifact: OtaArtifact, origin: string): string {
  const packageURL = `${origin}/api/deployments/ota/${artifact.id}/app.ipa`;
  const version = artifact.build || artifact.version;
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>${escapeXML(packageURL)}</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>${escapeXML(artifact.bundleId)}</string>
        <key>bundle-version</key>
        <string>${escapeXML(version)}</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>${escapeXML(artifact.title)}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
`;
}

/**
 * The page a phone opens from the install QR. It offers the OTA install and a
 * pairing link, so a fresh install connects to this hub without typing a URL.
 */
export function otaPage(artifact: OtaArtifact, origin: string, token: string): string {
  const manifestURL = `${origin}/api/deployments/ota/${artifact.id}/manifest.plist`;
  const installURL = `itms-services://?action=download-manifest&url=${encodeURIComponent(manifestURL)}`;
  const pairURL = `opencodebar://pair?url=${encodeURIComponent(origin)}&token=${encodeURIComponent(token)}`;
  const label = [artifact.version, artifact.build ? `(${artifact.build})` : ""]
    .filter(Boolean)
    .join(" ");
  const commit = artifact.commitSha ? artifact.commitSha.slice(0, 7) : "";
  const branch = artifact.branch || "";
  const details = [label && `Version ${escapeHTML(label)}`, commit && `Commit ${escapeHTML(commit)}`, branch && escapeHTML(branch)]
    .filter(Boolean)
    .join(" · ");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<title>Install ${escapeHTML(artifact.title)}</title>
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0; min-height: 100vh; display: flex; flex-direction: column;
    align-items: center; justify-content: center; gap: 12px; padding: 32px 24px;
    box-sizing: border-box; background: #101012; color: #f2f2f4;
    font: 16px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    text-align: center;
  }
  h1 { font-size: 26px; margin: 0; letter-spacing: -0.02em; }
  p { margin: 0; color: #9a9aa2; font-size: 14px; max-width: 30em; }
  .meta { color: #6f6f78; font-size: 12px; font-variant-numeric: tabular-nums; }
  a.button {
    display: block; width: min(320px, 100%); box-sizing: border-box;
    padding: 15px 22px; border-radius: 14px; text-decoration: none;
    font-weight: 700; font-size: 17px;
  }
  a.install { background: #30d158; color: #001b07; }
  a.pair { background: #2c2c31; color: #f2f2f4; }
  .hint { margin-top: 10px; font-size: 12px; color: #6f6f78; }
  .note { margin-top: 18px; font-size: 11px; color: #55555e; max-width: 30em; }
</style>
</head>
<body>
  <h1>${escapeHTML(artifact.title)}</h1>
  <p class="meta">${details || "Development build"}</p>
  <a class="button install" href="${escapeHTML(installURL)}">Install</a>
  <a class="button pair" href="${escapeHTML(pairURL)}">Pair this hub</a>
  <p class="hint">Install first, then tap “Pair this hub”.</p>
  <p class="note">The pairing link contains this hub’s token, so only open this page on your own devices.</p>
</body>
</html>
`;
}

function escapeXML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function escapeHTML(value: string): string {
  return escapeXML(value)
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

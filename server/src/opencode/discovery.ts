import { existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { configDir, opencodeDataDir } from "../config.ts";
import type { OpenCodeLocation } from "./errors.ts";

function readJSON(path: string): Record<string, unknown> | null {
  try {
    if (!existsSync(path)) return null;
    const value = JSON.parse(readFileSync(path, "utf8"));
    return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function envString(env: NodeJS.ProcessEnv, name: string): string | undefined {
  const value = env[name]?.trim();
  return value ? value : undefined;
}

async function runCommand(command: string[], timeoutMs: number): Promise<string | null> {
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn(command, {
      stdout: "pipe",
      stderr: "pipe",
      stdin: "ignore",
    });
  } catch {
    return null;
  }

  const read = (async () => {
    const output = await new Response(proc.stdout as ReadableStream).text();
    const code = await proc.exited;
    return code === 0 ? output : null;
  })();

  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<null>((resolve) => {
    timer = setTimeout(() => {
      try {
        proc.kill();
      } catch {
        // Already gone.
      }
      resolve(null);
    }, timeoutMs);
  });

  try {
    return await Promise.race([read, timeout]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function firstURL(text: string, requireLoopback = false): string | null {
  const matches = text.match(/https?:\/\/[A-Za-z0-9._-]+:[0-9]+/g) ?? [];
  let fallback: string | null = null;
  for (const candidate of matches.reverse()) {
    const loopback = candidate.includes("127.0.0.1") || candidate.includes("localhost");
    if (loopback) return candidate;
    if (!requireLoopback && !fallback) fallback = candidate;
  }
  return requireLoopback ? null : fallback;
}

async function opencodeBinary(env: NodeJS.ProcessEnv): Promise<string | null> {
  const home = env.HOME ?? "";
  const candidates = [
    join(home, ".opencode/bin/opencode"),
    "/opt/homebrew/bin/opencode",
    "/usr/local/bin/opencode",
    join(home, ".local/bin/opencode"),
  ];
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  for (const dir of (env.PATH ?? "").split(":")) {
    if (!dir) continue;
    const candidate = join(dir, "opencode");
    if (existsSync(candidate)) return candidate;
  }
  const found = await runCommand(["/bin/zsh", "-lc", "command -v opencode"], 3_000);
  const trimmed = found?.trim();
  return trimmed && existsSync(trimmed) ? trimmed : null;
}

async function logURL(env: NodeJS.ProcessEnv): Promise<string | null> {
  const log = join(opencodeDataDir(env), "log/opencode.log");
  try {
    const size = statSync(log).size;
    const start = Math.max(0, size - 512 * 1024);
    const text = await Bun.file(log).slice(start).text();
    return firstURL(text, true);
  } catch {
    return null;
  }
}

/**
 * Finds the local OpenCode service. Mirrors the macOS app's discovery order:
 * explicit environment, `opencode service status`, lsof, then the server log.
 */
export async function discoverOpenCode(
  env: NodeJS.ProcessEnv = process.env,
): Promise<OpenCodeLocation | null> {
  const service = readJSON(join(configDir(env), "service.json"));
  const password =
    envString(env, "OPENCODE_SERVICE_PASSWORD") ??
    (typeof service?.password === "string" ? service.password : undefined);

  const explicit = envString(env, "OPENCODEBAR_OPENCODE_URL") ?? envString(env, "OPENCODE_SERVICE_URL");
  const url = explicit ?? (await discoverURL(env));
  if (!url || !password) return null;
  return { url: url.replace(/\/+$/, ""), password };
}

async function discoverURL(env: NodeJS.ProcessEnv): Promise<string | null> {
  const binary = await opencodeBinary(env);
  if (binary) {
    const status = await runCommand([binary, "service", "status"], 4_000);
    const url = status ? firstURL(status) : null;
    if (url) return url;
  }

  const lsof = await runCommand(
    ["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "opencode"],
    4_000,
  );
  const lsofURL = lsof ? firstURL(lsof, true) : null;
  if (lsofURL) return lsofURL;

  return logURL(env);
}

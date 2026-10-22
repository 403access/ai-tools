import {
  HUB_VERSION,
  lanAddresses,
  loadConfig,
  pairingLink,
  writeHubConfig,
} from "./config.ts";
import { createHandler } from "./api.ts";
import { HubDB } from "./db.ts";
import { Hub } from "./hub.ts";

const config = loadConfig();
const db = new HubDB(config.dbPath);
const hub = new Hub(config, db);
const handler = createHandler({
  db,
  hub,
  config,
  restart: restartHub,
  persistSettings: (settings) => writeHubConfig(settings, settings.port),
});

/**
 * Binds the HTTP server. If the configured port is busy and it was not set
 * explicitly, walk forward a few ports — the chosen port is written to the
 * config file, so clients follow along without any setup.
 */
function listen(): ReturnType<typeof Bun.serve> {
  const explicit = Boolean(process.env.OPENCODEBAR_HUB_PORT);
  let port = config.port;
  for (let attempt = 0; ; attempt += 1) {
    try {
      const server = Bun.serve({
        hostname: config.host,
        port,
        fetch: handler,
        idleTimeout: 255,
      });
      if (port !== config.port) {
        console.log(`[hub] port ${config.port} was busy — using ${port}`);
      }
      return server;
    } catch (error) {
      if (explicit || attempt >= 10) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`[hub] could not bind port ${port}: ${message}`);
        if (!explicit) {
          console.error("[hub] Set OPENCODEBAR_HUB_PORT to a free port and retry.");
        }
        process.exit(1);
      }
      port += 1;
    }
  }
}

const server = listen();

config.port = server.port ?? config.port;
const port = config.port;
writeHubConfig(config, port);
hub.start();

const lan = lanAddresses(port);
const local = `http://127.0.0.1:${port}`;

console.log("");
console.log(`  OpenCodeBar Hub ${HUB_VERSION}`);
console.log(`  ─────────────────────────────────────────────`);
console.log(`  Listen     http://${config.host}:${port}`);
console.log(`  Local      ${local}`);
for (const entry of lan) {
  console.log(`  LAN        ${entry.url}  (${entry.interface})`);
}
console.log(`  Database   ${config.dbPath}`);
console.log(`  Config     ${config.configPath}`);
console.log(`  Token      ${config.token}`);
if (lan[0]) {
  console.log(`  Pairing    ${pairingLink(lan[0].url, config.token)}`);
}
console.log("");

setTimeout(() => {
  const health = hub.health();
  const opencode = health.opencode;
  if (opencode.connected) {
    console.log(
      `[hub] OpenCode connected${opencode.version ? ` (v${opencode.version})` : ""} · ${health.sessions} sessions cached`,
    );
  } else {
    console.log(
      `[hub] Waiting for OpenCode${opencode.lastError ? `: ${opencode.lastError}` : "…"}`,
    );
  }
}, 3_000);

/**
 * Relaunches the hub for the settings screen's restart action. The HTTP server
 * is stopped and closed first so the replacement can bind the same port; the
 * new process inherits stdio, so `make hub` keeps printing to the terminal.
 */
let restarting = false;
function restartHub(): void {
  if (restarting) return;
  restarting = true;
  console.log("[hub] Restarting…");

  hub.stop();
  try {
    server.stop(true);
  } catch {
    // Already stopped.
  }
  try {
    db.close();
  } catch {
    // Already closed.
  }

  // Give the socket a moment to be released before the replacement starts.
  setTimeout(() => {
    try {
      const child = Bun.spawn({
        cmd: [process.execPath, ...process.argv.slice(1)],
        cwd: process.cwd(),
        env: process.env,
        stdio: ["ignore", "inherit", "inherit"],
      });
      child.unref();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`[hub] Restart failed: ${message}`);
    }
    process.exit(0);
  }, 250);
}

let shuttingDown = false;
function shutdown(): void {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log("\n[hub] Stopping…");
  hub.stop();
  server.stop();
  db.close();
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

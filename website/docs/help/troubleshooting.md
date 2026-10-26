---
title: Troubleshooting
sidebar_position: 1
---

# Troubleshooting

## The hub will not start

**Port already in use**

If you did not set `OPENCODEBAR_HUB_PORT`, the hub walks forward up to ten
ports and writes the chosen one to the config file. If you did set it, a busy
port is fatal:

```bash
lsof -nP -iTCP:8787 -sTCP:LISTEN
OPENCODEBAR_HUB_PORT=8788 make hub
```

**Bun is missing**

```bash
curl -fsSL https://bun.sh/install | bash
bun --version
```

**Database permission error**

The hub creates `~/.local/share/opencodebar/hub.sqlite`. Make sure the directory
is writable by your user. Deleting the database is safe if it is corrupted.

## The hub cannot find OpenCode

Check the service directly:

```bash
opencode service status
```

The hub reads the password from `~/.config/opencode/service.json` (or
`$XDG_CONFIG_HOME/opencode/service.json`) and tries `opencode service status`,
`lsof`, then the server log. If discovery still fails, set the URL and password
explicitly:

```bash
OPENCODEBAR_OPENCODE_URL=http://127.0.0.1:4096 \
OPENCODE_SERVICE_PASSWORD=... \
make hub
```

## The Mac app says offline

- Confirm the hub is running: `curl http://127.0.0.1:8787/api/ping`.
- Check `~/.config/opencode/opencodebar-hub.json` for the current URL and token.
- If the hub moved ports, restart the app so it re-reads the file.
- Check **Settings → Server** for the last error.

Environment overrides take precedence over the generated file. Unset
`OPENCODEBAR_HUB_URL` / `OPENCODEBAR_HUB_TOKEN` if they point at an old hub.

## A turn fails with “This Go model trains on request data”

This is a policy rejection from OpenCode/your Go workspace, not a hub or
OpenCodeBar error. Do **not** enable **Allow paid endpoints that train on
request data** just to make the model work. OpenCode CLI does not require it,
and OpenCodeBar never changes that setting for you.

Instead:

- open **Retry with settings…** on the failed turn and choose a model whose
  data-use policy you accept, or
- set a non-training model as OpenCode's default for that directory.

The failed session stays unchanged; retrying creates a forked session before
the failed prompt. See [Session detail → Models and data
training](../using/session.md#models-and-data-training).

## The phone cannot connect

- Use the Mac's LAN address, not `127.0.0.1`.
- Put both devices on the same Wi-Fi network.
- On cellular, or when the Mac is not reachable on the LAN, run
  `make hub-tunnel` on the Mac and use the printed HTTPS URL (or rerun
  `make mobile-device`, which picks it up automatically).
- USB tethering does not route back to the Mac. The Mac can use the phone's
  data, but iOS apps cannot reach `192.0.0.2`, so use the tunnel there too.
- Allow **Local Network** access for OpenCodeBar on both devices.
- Allow incoming connections for Bun/the hub port in the macOS firewall.
- A sleeping Mac cannot answer. Open **Settings → Power** on the Mac and turn on
  **Keep Mac awake** (or start the hub with `OPENCODEBAR_PREVENT_SLEEP=1`).
  Closing the lid still puts the Mac to sleep.
- Test from another device: `curl http://<mac-lan-ip>:8787/api/ping`.

If you bound the hub to `127.0.0.1`, the phone cannot reach it. Use
`OPENCODEBAR_HUB_HOST=0.0.0.0` on a trusted network, or a tunnel.

## Pairing link is rejected

The link must start with `opencodebar://pair?url=…&token=…`. If the token was
regenerated, the old link or QR code no longer works. Copy or scan a fresh one
from the hub output or from **Settings → Pairing**.

## Stats stay on “Measuring this session…”

Session stats page through message history the first time they are requested.
Very long sessions can take a few seconds. The tab reports when totals cover
only the loaded window. Keep the hub running and retry; repeated requests are
cached.

## Changes appear empty

Changes are extracted from edit/write tool calls in cached messages. The first
open of a session hydrates its history. Project changes hydrate the newest ten
sessions by default; open an old session's Changes tab, or use
`/api/project/{id}/changes?sessions=50`, to include more.

## Go plan limits are hidden or stale

- Hidden: no usage key was resolved. See [Go plan usage](../hub/go-usage.md).
- `401 api_key_expired`: the key in `auth.json` expired. Add a service-account
  key to `opencodebar.json`.
- Stale: the usage endpoint is unreachable; cached values are shown.

## Device build fails

- Sign in to Xcode under **Settings → Accounts**.
- Set a team explicitly: `make mobile-device DEVELOPMENT_TEAM=ABCDE12345`.
- Enable Developer Mode on the device.
- Unlock and trust the Mac.
- If several devices are connected, pass `DEVICE=…`.

## Docs build fails

```bash
cd website
npm ci
npm run build
```

Broken internal links fail the build by design. Run `make docs` to see the
failing page. If `npm ci` complains about the lockfile, run `npm install` once
and commit `package-lock.json`.

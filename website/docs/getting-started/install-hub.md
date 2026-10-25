---
title: Install and run the hub
sidebar_position: 2
---

# Install and run the hub

The hub is a Bun + TypeScript + SQLite server in `server/`. It discovers the
local OpenCode service, caches its data, and serves the Mac and iOS apps.

## Clone and start

```bash
git clone https://github.com/403access/ai-tools.git
cd ai-tools
make hub
```

`make hub` installs the server dependencies and starts the process in the
foreground. On first run it generates a token and prints something like:

```text
  OpenCodeBar Hub 1.0.0
  ─────────────────────────────────────────────
  Listen     http://0.0.0.0:8787
  Local      http://127.0.0.1:8787
  LAN        http://192.168.1.20:8787  (en0)
  Database   ~/.local/share/opencodebar/hub.sqlite
  Config     ~/.config/opencode/opencodebar-hub.json
  Token      <generated>
  Pairing    opencodebar://pair?url=…&token=…
```

Keep the terminal open while you use the apps.

:::tip
Run the hub in a separate terminal from the Mac app. `make hub` is a foreground
process by design; if the terminal exits, the server stops.
:::

## What happens on the first run

1. The hub reads the OpenCode password from
   `~/.config/opencode/service.json` (or `$XDG_CONFIG_HOME/opencode/service.json`).
2. It discovers the OpenCode URL from `opencode service status`, then `lsof`,
   then the server log.
3. It creates `~/.local/share/opencodebar/hub.sqlite` and starts polling.
4. It writes the connection details to
   `~/.config/opencode/opencodebar-hub.json` with owner-only permissions.

The Mac app reads that generated file automatically. The phone pairs with the
URL and token, or the pairing link.

## Ports

The default port is `8787`. If it is busy and you did **not** set
`OPENCODEBAR_HUB_PORT`, the hub tries the next ten ports and writes the port it
actually bound into the config file. Clients follow the file, so no manual
change is needed.

To force a port:

```bash
OPENCODEBAR_HUB_PORT=8788 make hub
```

## Check that it is alive

```bash
curl http://127.0.0.1:8787/api/ping
```

`/api/ping` is the only unauthenticated API endpoint besides the API
documentation (`/api/docs` and `/api/openapi.json`). It returns the hub version
so a client can verify a URL before sending its token.

For an authenticated health check:

```bash
TOKEN=$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/opencode/opencodebar-hub.json")))["token"])')
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8787/api/health
```

## Development mode

```bash
make hub-dev    # auto-reload on server changes
make hub-test   # Bun database and API tests
```

## Run it without a terminal

The hub is a normal Bun process, so you can wrap it in a `launchd` agent if you
want it to survive logout or run at login. Keep in mind that only one hub should
own a given SQLite database and OpenCode service at a time.

## Reach it from another network

The hub listens on `0.0.0.0`, so a phone on the same Wi-Fi can use the LAN
address. On cellular, or on a different network, start a Cloudflare quick tunnel
in a second terminal:

```bash
make hub-tunnel
```

It prints a public HTTPS URL and a pairing link, and writes
`~/.config/opencode/opencodebar-hub-tunnel.json` so `make mobile-device` and the
Mac app's QR code use it while it runs. No Cloudflare account is required, but
the URL changes each time and only works while the process is alive. Every
request still requires the hub token.

For a stable private address, use Tailscale on the Mac and the phone and pair
with the Mac's `100.x.y.z` address. See [Security](../hub/security.md) before
exposing the hub.

## Where the data lives

| Path | Purpose |
| --- | --- |
| `~/.local/share/opencodebar/hub.sqlite` | Cached sessions, messages, changes, stats, devices, and usage |
| `~/.config/opencode/opencodebar-hub.json` | Generated URL/token for clients (mode `0600`) |
| `~/.config/opencode/opencodebar.json` | Optional app overrides, including a usage-only key |
| `~/.local/share/opencode/auth.json` | OpenCode credentials, used only as a Go usage key fallback |

Deleting the SQLite file is safe; the hub recreates it and rebuilds the cache.
Deleting the config file changes the token, so pair the phone again.

Next: [run the Mac app](mac-app.md) or [run the iOS app](ios-app.md).

---
title: Configuration
sidebar_position: 2
---

# Configuration

The hub is configured with environment variables and a small generated JSON
file. Client overrides work the same way.

## Hub environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENCODEBAR_HUB_PORT` | `8787` | Port to bind; if set, no automatic fallback |
| `OPENCODEBAR_HUB_HOST` | `0.0.0.0` | Interface to bind; use `127.0.0.1` for local-only |
| `OPENCODEBAR_HUB_TOKEN` | generated | Fixed Bearer token instead of a generated one |
| `OPENCODEBAR_HUB_DB` | `~/.local/share/opencodebar/hub.sqlite` | SQLite database path |
| `OPENCODEBAR_OPENCODE_URL` | discovered | OpenCode service URL |
| `OPENCODE_SERVICE_URL` | discovered | Alias for the OpenCode URL |
| `OPENCODE_SERVICE_PASSWORD` | from `service.json` | OpenCode Basic-auth password |
| `OPENCODEBAR_FAST_POLL_MS` | `5000` | Fast poll interval |
| `OPENCODEBAR_SLOW_POLL_MS` | `60000` | Slow poll interval |
| `OPENCODEBAR_USAGE_POLL_MS` | `60000` | Go usage poll interval |
| `OPENCODEBAR_EVENT_THROTTLE_MS` | `250` | Coalescing window for event updates sent to the apps; `0` forwards every event |
| `OPENCODEBAR_PREVENT_SLEEP` | `false` | Keep a macOS idle-sleep assertion while the hub runs (`1`/`true`/`on`) |
| `OPENCODEBAR_REMOTE` | enabled | Set to `0`/`false`/`off` to disable remote desktop |
| `OPENCODEBAR_REMOTE_HOST` | auto-detected | Path to the `OpenCodeBarRemoteHost` helper |
| `OPENCODEBAR_VM_DIR` | `~/.local/share/opencodebar/vms` | VM definitions, disks, keys, and logs |
| `OPENCODEBAR_VZ_HELPER` | auto-detected | Path to the `OpenCodeBarVZ` helper |
| `OPENCODEBAR_NIX` | auto-detected | Path to the `nix` binary |
| `OPENCODEBAR_NIXOS_CHANNEL` | `nixos-26.05` | Default channel for new NixOS guests |
| `OPENCODEBAR_LOG_LEVEL` | `info` | `debug`, `info`, or `warn` |
| `OPENCODE_GO_USAGE_URL` | OpenCode console endpoint | Override the usage endpoint |
| `OPENCODE_GO_USAGE_KEY` | resolved | Usage-only key |
| `OPENCODE_API_KEY` | resolved | Fallback usage key |

`XDG_CONFIG_HOME` and `XDG_DATA_HOME` are respected when resolving config and
database paths.

The update throttle and sleep preference are also editable from the Mac app's
**Settings → Updates** and **Settings → Power** (or `PATCH /api/settings`). The
hub applies changes immediately and records the values in
`opencodebar-hub.json`, so they survive a restart. An environment variable still
wins over the saved value.

## Virtual machine prerequisites

The VMs tab is read-only until three host pieces are ready. The setup card can
run two of them:

- **Install Nix** runs the official installer through a macOS administrator
  prompt. The password dialog appears on the Mac; the hub never receives the
  password, and the installer log streams back to the app.
- **Build VM helper** runs `make vz-helper` and streams the build/signing output.

The hub only accepts those fixed steps; clients cannot send arbitrary commands.
The Linux builder still needs a terminal because it must keep running:

```sh
# Start a NixOS builder VM so Nix can build aarch64-linux images on macOS.
nix run nixpkgs#darwin.linux-builder
```

`GET /api/vms/capabilities` reports `helperAvailable`, `helperEntitled`,
`nixAvailable`, and `linuxBuilder`, and the VMs tab prints the same diagnosis.
Set `OPENCODEBAR_NIX` if the hub cannot find Nix from a GUI launch, and
`OPENCODEBAR_VZ_HELPER` to use a helper outside `.build/` or `dist/`.

## Generated files

| Path | Contents |
| --- | --- |
| `~/.config/opencode/opencodebar-hub.json` | Hub URL, token, port, version (mode `0600`) |
| `~/.local/share/opencodebar/hub.sqlite` | Cache and device registry (WAL mode) |
| `~/.local/share/opencodebar/vms/{id}/` | VM definition, `configuration.nix`, flake, raw disk, SSH key, logs |
| `~/.config/opencode/opencodebar.json` | Optional app config (`hubURL`, `hubToken`, `goUsageKey`) |
| `~/.local/share/opencode/auth.json` | OpenCode credentials; final fallback for a Go key |
| `~/Library/Caches/OpenCodeBar/usage.json` | macOS last-known usage cache |

The generated hub file is rewritten every time the hub starts, including when it
falls back to another port. Clients read it automatically.

## Port fallback

If `OPENCODEBAR_HUB_PORT` is **not** set and the configured port is busy, the hub
walks forward up to ten ports. The chosen port is written to the generated
config, so the Mac and phone clients follow it.

If you set `OPENCODEBAR_HUB_PORT` explicitly, a busy port is a hard error.

## Client overrides

The native clients resolve the hub in this order:

1. `$OPENCODEBAR_HUB_URL` / `$OPENCODEBAR_HUB_TOKEN`
2. `hubURL` / `hubToken` in `~/.config/opencode/opencodebar.json`
3. `~/.config/opencode/opencodebar-hub.json`

Example `opencodebar.json`:

```json
{
  "hubURL": "http://192.168.1.20:8787",
  "hubToken": "replace-with-your-token",
  "goUsageKey": "oc_sk_..."
}
```

GUI-launched apps may not inherit shell environment variables, so the config
file is the more reliable place for GUI overrides.

## Go usage key

The key is resolved in this order:

1. `$OPENCODE_GO_USAGE_KEY`
2. `$OPENCODE_API_KEY`
3. `goUsageKey` in `~/.config/opencode/opencodebar.json`
4. the `opencode-go` then `opencode` key in
   `~/.local/share/opencode/auth.json`

A console service-account key (`oc_sk_…`, inference-only) works against the
usage endpoint and avoids replacing the credential OpenCode uses for inference.
See [Go plan usage](go-usage.md).

## Examples

Bind to loopback and use a different database:

```bash
OPENCODEBAR_HUB_HOST=127.0.0.1 \
OPENCODEBAR_HUB_DB="$HOME/.local/share/opencodebar/dev.sqlite" \
make hub
```

Increase polling only for a busy local service:

```bash
OPENCODEBAR_FAST_POLL_MS=10000 OPENCODEBAR_SLOW_POLL_MS=120000 make hub
```

Batch event updates more aggressively for a busy session or a slow phone link:

```bash
OPENCODEBAR_EVENT_THROTTLE_MS=500 make hub
```

Keep the Mac awake so the phone keeps its connection:

```bash
OPENCODEBAR_PREVENT_SLEEP=1 make hub
```

Debug logging:

```bash
OPENCODEBAR_LOG_LEVEL=debug make hub
```

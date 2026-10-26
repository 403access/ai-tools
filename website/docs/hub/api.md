---
title: API reference
sidebar_position: 3
---

# API reference

The hub exposes a small HTTP API that mirrors OpenCode's shapes, adds cached
reads, and forwards writes.

## Base URL

```text
http://<mac-host>:8787
```

The hub writes the actual URL and port to
`~/.config/opencode/opencodebar-hub.json`.

## Interactive documentation

Every hub serves Swagger UI at **`/api/docs`** and the underlying OpenAPI 3.0
document at **`/api/openapi.json`**:

```text
http://127.0.0.1:8787/api/docs
```

Both routes are public. Click **Authorize** in Swagger UI, enter the token from
`~/.config/opencode/opencodebar-hub.json`, and every **Try it out** request sends
it automatically. A link with `?token=…` pre-authorizes the page, so a bookmark
can open with **Try it out** ready to go. The specification is generated from
[`server/src/openapi/`](https://github.com/403access/ai-tools/tree/main/server/src/openapi),
so it ships with the hub and stays in step with the routes.

A published copy of the same explorer is available at
[`403access.github.io/ai-tools/docs/api`](https://403access.github.io/ai-tools/docs/api/),
with the generated spec at
[`openapi.json`](https://403access.github.io/ai-tools/docs/api/openapi.json). It
is generated from the hub source during the docs build and is reference-only —
executing requests needs a running hub, so use the `/api/docs` URL printed by
`make hub` for that.

## Authentication

Every endpoint except `GET /api/ping`, `GET /api/docs`, and
`GET /api/openapi.json` requires the Bearer token:

```bash
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8787/api/health
```

For SSE clients that cannot set headers, the token may also be passed as
`?token=…`. Prefer the header.

```bash
TOKEN=$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/opencode/opencodebar-hub.json")))["token"])')
```

## Device headers

Clients identify themselves so the Settings screen can list connected devices:

| Header | Example | Notes |
| --- | --- | --- |
| `X-OpenCodeBar-Device-Id` | stable UUID | Required to register a device; survives reinstalls |
| `X-OpenCodeBar-Device-Name` | `Oli's MacBook` | Defaults to `Unknown device` |
| `X-OpenCodeBar-Platform` | `macOS`, `iOS`, `iPadOS` | Defaults to `unknown` |
| `X-OpenCodeBar-App-Version` | `1.0.0` | Optional |

Headers are optional for basic API use. A request without a device id does not
appear in the device list. The Mac app derives its id from the machine's
hardware UUID; the iOS app keeps its id in the keychain. When a known device
reconnects with a new id, the hub folds the old row into the new one instead of
listing the device twice.

## Responses

JSON responses are `application/json; charset=utf-8` with `Cache-Control:
no-store`. Most collection endpoints wrap the payload:

```json
{ "data": [] }
```

Errors use:

```json
{ "error": { "message": "Session not found" } }
```

CORS allows any origin, with `Authorization`, `Content-Type`, and
`Last-Event-ID` headers.

## Endpoints

### Health and info

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/ping` | Unauthenticated liveness probe and hub version |
| `GET` | `/api/health` | Hub, OpenCode, device, and cache health |
| `GET` | `/api/hub/info` | Alias for health |
| `GET` | `/api/info` | Server info, URLs, capabilities, and hub health |
| `GET` | `/api/system` | Full snapshot of the machine running the hub |
| `GET` | `/api/system/apps/icon?path=…` | Icon artwork for one installed app, when available |
| `GET` | `/api/system/apps/detail?path=…` | Bundle facts and app-specific inventory for one installed app |
| `POST` | `/api/system/apps/action` | Manage an app's resources (Xcode simulators) |
| `GET` | `/api/terminals` | Terminals across OpenCode locations |
| `POST` | `/api/terminals` | Start a PTY |
| `GET` | `/api/terminals/{id}` | One terminal |
| `PUT` | `/api/terminals/{id}` | Rename or resize a terminal |
| `DELETE` | `/api/terminals/{id}` | Stop and remove a terminal |
| `GET` | `/api/terminals/{id}/socket` | WebSocket for terminal I/O |
| `GET` | `/api/host-terminals` | Tabs open in Terminal.app |
| `GET` | `/api/host-terminals/{tty}` | Terminal.app text mirror |
| `POST` | `/api/host-terminals/{tty}/command` | Run a line in Terminal.app |
| `POST` | `/api/host-terminals/{tty}/focus` | Focus a Terminal.app tab |
| `GET` | `/api/vms` | Virtual-machine definitions and status |
| `GET` | `/api/vms/capabilities` | Host support, helper/Nix/builder readiness |
| `GET` | `/api/vms/catalog` | Categories, clickable options, presets, and defaults |
| `POST` | `/api/vms/preview` | Render a draft configuration and build plan |
| `POST` | `/api/vms` | Create a NixOS VM definition and start its build |
| `GET` | `/api/vms/{id}` | One VM with metrics |
| `PATCH` | `/api/vms/{id}` | Rename, resize, replace packages, or replace the builder config |
| `POST` | `/api/vms/{id}/preview` | Render a configuration against a real VM |
| `DELETE` | `/api/vms/{id}` | Stop the helper and remove the VM |
| `POST` | `/api/vms/{id}/{action}` | Start, stop, restart, pause, resume, rebuild, or apply |
| `GET` | `/api/vms/{id}/log` | Build, serial, or apply log tail |
| `GET` | `/api/vms/{id}/console/socket` | WebSocket for the serial console |
| `GET` | `/api/vms/setup` | Current host setup job and streamed log |
| `POST` | `/api/vms/setup` | Run the fixed Nix or helper setup step |
| `POST` | `/api/vms/setup/cancel` | Cancel a running setup job |
| `GET` | `/api/vms/setup/logs` | Stored setup logs, including rotated runs |
| `GET` | `/api/vms/setup/log` | Latest Nix, helper, or builder log tail |
| `GET` | `/api/remote` | Capture helper status, displays, and permissions |
| `POST` | `/api/remote/configure` | Change fps, quality, max width, or display |
| `POST` | `/api/remote/permissions` | Request Screen Recording / Accessibility |
| `GET` | `/api/remote/socket` | WebSocket for frames, status, and input |
| `GET` | `/api/devices` | Connected devices |
| `GET` | `/api/settings` | Tunable hub settings |
| `PATCH` | `/api/settings` | Update the event throttle or sleep preference |

`/api/settings` returns the coalescing window applied to event-stream updates
and whether the hub host is allowed to idle-sleep:

```json
{
  "data": {
    "eventThrottleMs": 250,
    "eventThrottleMinMs": 0,
    "eventThrottleMaxMs": 5000,
    "preventSleep": false,
    "preventSleepSupported": true
  }
}
```

`GET /api/system` collects the host machine's inventory. Dynamic fields (CPU,
memory, disks, processes, ports, Docker) are refreshed every request; expensive
ones (installed apps, Homebrew, toolchain versions, displays, security flags) are
cached for five minutes. `?refresh=1` skips both the two-second snapshot cache
and the inventory cache, which the System tab uses for its manual refresh. The
response is wrapped in `{ "data": { … } }` and includes:

| Section | Contents |
| --- | --- |
| `host` / `platformName` | macOS, Linux or Windows, version, kernel, architecture, model, chip, boot time, user, shell, timezone, VM detection |
| `hub` | Hub version, PID, runtime, uptime, port, database path/size, process memory |
| `cpu` / `memory` | Model, cores, clock, overall and per-core usage, load averages, RAM breakdown, swap |
| `disks` / `network` | Mounted volumes, filesystem and capacity; interfaces, addresses, gateway, DNS |
| `battery` / `thermal` / `security` | Battery health and cycles; thermal pressure; SIP, FileVault, firewall, Gatekeeper, SELinux, AppArmor, Defender |
| `media` | Now-playing sessions: owning app, bundle id, title, artist, album, state, elapsed/duration, audio or video |
| `processes` | Total process count, the top 12 rows by CPU, and the top 50 by memory |
| `apps` | Installed applications with path, version, bundle id, source, architecture, and whether icon artwork is available |
| `homebrew` | Version, prefix, formula/cask counts, outdated markers, full package list |
| `runtimes` | Installed developer runtimes and tools with versions and paths |
| `listeningPorts` | Listening TCP ports with process names and PIDs |
| `docker` / `displays` | Container state when the daemon is reachable; GPUs and monitors |

Every collector is optional: fields a platform cannot provide are omitted rather
than reported as zero.

`GET /api/system/apps/icon` accepts the `path` of an app from that snapshot and
returns its PNG artwork plus an `ETag`. Apps whose bundles have no usable
artwork report `hasIcon: false` and return `404` here, so clients can keep the
generic app glyph.

`GET /api/system/apps/detail` accepts the same `path` and returns the facts
clients show on an app's detail page: display name, bundle id, version and
build, minimum OS, executable, recursive bundle size, URL schemes, document
types, extensions, and the signing authority. Only apps in the current snapshot
are accepted, so the endpoint cannot probe arbitrary folders.

Apps with a dedicated provider include more inventory. Xcode returns a `xcode`
object with its developer directory, SDKs, the frameworks shipped in its
platform toolchains, and simulator runtimes with every device and its state:

```json
{
  "data": {
    "app": { "name": "Xcode", "path": "/Applications/Xcode.app" },
    "info": { "bundleID": "com.apple.dt.Xcode", "version": "27.1" },
    "xcode": {
      "developerDir": "/Applications/Xcode.app/Contents/Developer",
      "simulators": [{
        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
        "name": "iOS 18.0",
        "platform": "iOS",
        "version": "18.0",
        "available": true,
        "devices": [{
          "udid": "1A2B3C4D-…",
          "name": "iPhone 16 Pro",
          "state": "Booted",
          "available": true
        }]
      }],
      "sdks": [{ "name": "iOS 18.0", "platform": "iphoneos" }],
      "frameworks": [{ "name": "XcodeKit", "platform": "Xcode" }]
    }
  }
}
```

`POST /api/system/apps/action` manages those extras. The body carries the app
`path`, an `action`, and a `target` id. Supported actions are
`simulator.boot`, `simulator.shutdown`, `simulator.erase`,
`simulator.delete`, and `runtime.delete`. The target must already exist in the
current inventory, so requests cannot pass arbitrary arguments to `simctl`. The
response is the refreshed detail page.

### Media controls

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/api/media` | Playback or system-volume command |

```json
{ "action": "toggle" }
{ "action": "next" }
{ "action": "play" }
{ "action": "pause" }
{ "action": "previous" }
{ "action": "back15" }
{ "action": "forward15" }
{ "action": "mute", "value": 1 }
{ "action": "volume", "value": 65 }
```

The response carries the updated `media` and `audio` state:

```json
{
  "data": {
    "media": [{ "app": "Google Chrome", "state": "playing", "title": "…" }],
    "audio": { "volumePercent": 65, "muted": false, "controllable": true }
  }
}
```

macOS sends MediaRemote commands to the current system player and falls back to
AppleScript for Music and Spotify. Linux uses `playerctl` and `pactl`. Playback
commands return `409` when nothing is playing; unknown actions return `400`.

### Terminals

Terminals are OpenCode's PTY sessions, proxied by the hub so a remote client can
list and drive them with only the hub token.

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/terminals` | Every terminal across known locations |
| `POST` | `/api/terminals` | Create a PTY |
| `GET` | `/api/terminals/{id}` | One cached terminal |
| `PUT` | `/api/terminals/{id}` | Rename or resize |
| `DELETE` | `/api/terminals/{id}` | Stop and remove the PTY |
| `GET` | `/api/terminals/{id}/socket` | WebSocket for output and input |

`GET /api/terminals` returns `{ "data": [ … ] }`. OpenCode scopes PTYs by
location, so the hub queries the service's default location plus every cached
project directory, merges the results, and annotates each row with its
`location`:

```json
{
  "id": "pty_123",
  "title": "Build",
  "command": "/bin/zsh",
  "args": ["-l"],
  "cwd": "/Users/you/src/app",
  "status": "running",
  "pid": 4321,
  "location": "/Users/you/src/app"
}
```

`?refresh=1` bypasses the hub's short list cache. Exited PTYs stay listed until
OpenCode evicts them or a client removes them; `exitCode` is present once the
process has exited.

Create one with an optional `title`, `cwd`, `command`, `args`, `env`, and the
`location` whose terminal registry should own it. When `location` is omitted the
service's default location is used, and `cwd` defaults to that directory:

```json
{ "title": "Tests", "location": "/Users/you/src/app" }
```

Update accepts `title` and/or `size` (`rows`, `cols`). Resizing is an HTTP call
because normal PTYs do not carry resize frames on the socket:

```json
{ "size": { "rows": 40, "cols": 120 } }
```

`PUT` and `DELETE` take the terminal's `location` from the JSON body or the
`?location=` query parameter; the hub remembers locations it has listed, so the
query is normally only needed for the first request after a restart.

#### Terminal socket

Connect with `GET /api/terminals/{id}/socket?location=…&cursor=…` and the same
Bearer token as every other endpoint. The hub opens the upstream OpenCode socket
and forwards frames without modification:

- **Server → client:** text frames are raw terminal output. One binary control
  frame starts with `0x00` and carries `{"cursor": <absolute output position>}`;
  it marks the end of the retained replay.
- **Client → server:** text frames are raw terminal input, byte for byte. Send
  `\r` for Enter, not `\n`.
- Pass the last `cursor` when reconnecting to receive only output after that
  position. Omit it for a full replay of the retained buffer.

When the shell exits, OpenCode closes the socket; the PTY remains in the list
until it is removed.

### Virtual machines

The hub owns declarative NixOS guests and drives a detached
`OpenCodeBarVZ` helper for each running guest. Definitions live under
`~/.local/share/opencodebar/vms/` (override with `OPENCODEBAR_VM_DIR`); the
helper listens on loopback only and the hub proxies its serial console.

`GET /api/vms/capabilities` reports what the host can do:

```json
{
  "data": {
    "supported": true,
    "platform": "darwin",
    "arch": "arm64",
    "helperPath": "/…/.build/debug/OpenCodeBarVZ",
    "helperAvailable": true,
    "helperEntitled": true,
    "nixPath": "/nix/var/nix/profiles/default/bin/nix",
    "nixAvailable": true,
    "nixVersion": "nix (Nix) 2.28.3",
    "linuxBuilder": true,
    "linuxBuilderDetail": null,
    "storageDir": "/Users/you/.local/share/opencodebar/vms",
    "defaultChannel": "nixos-26.05",
    "defaultCPU": 4,
    "defaultMemoryMB": 4096,
    "maxCPU": 7,
    "maxMemoryMB": 12288,
    "notes": []
  }
}
```

Create one with a name, optional resources, and either a builder `config` or a
legacy package list:

```json
{
  "name": "NixOS dev",
  "cpuCount": 4,
  "memoryMB": 4096,
  "diskGB": 20,
  "channel": "nixos-26.05",
  "config": {
    "version": 1,
    "preset": "developer",
    "enabled": ["zram", "docker", "tailscale", "neovim", "nodejs"],
    "settings": {
      "timezone": "UTC",
      "locale": "en_US.UTF-8",
      "keymap": "us",
      "firewall": true,
      "passwordAuthentication": false,
      "extraTCPPorts": [8080],
      "extraUDPPorts": []
    },
    "users": [
      {
        "name": "alice",
        "description": "Alice",
        "groups": ["wheel", "docker"],
        "shell": "zsh",
        "sshKeys": ["ssh-ed25519 AAAAC3Nza… alice@example"],
        "passwordlessSudo": false,
        "createHome": true
      }
    ],
    "extraPackages": ["ripgrep"],
    "extraConfig": ""
  },
  "autostart": true
}
```

`GET /api/vms/catalog` returns every category, option, preset, and default. Each
option includes its category, icon/tint hints, tags, package attributes,
requirements, recommendations, conflicts, ports, and service names. The Nix
module body stays on the hub.

`POST /api/vms/preview` and `POST /api/vms/{id}/preview` render the real
`configuration.nix` and report the resolved plan without writing or building
anything:

```json
{
  "data": {
    "configuration": "# Managed by OpenCodeBar …",
    "flake": "{ … }",
    "packages": ["curl", "git", "htop", "nodejs", "ripgrep", "vim"],
    "services": ["Docker Engine", "Tailscale"],
    "ports": [8080, 11434],
    "users": ["opencodebar", "alice"],
    "optionCount": 5,
    "added": [],
    "warnings": [],
    "sizeMB": 2100,
    "stateVersion": "26.05"
  }
}
```

The response is `201` with a `building` VM. The build runs asynchronously; poll
the VM or its build log. A VM object includes `status`, `progress`,
`lastError`, resources, packages, pending packages, pending builder changes,
the builder config, SSH information, the discovered network address, paths, and
the last metrics snapshot:

```json
{
  "id": "vm_abcdef123456",
  "name": "NixOS dev",
  "distro": "nixos",
  "channel": "nixos-26.05",
  "status": "running",
  "cpuCount": 4,
  "memoryMB": 4096,
  "diskGB": 20,
  "packages": ["nodejs"],
  "pendingPackages": [],
  "pendingConfig": false,
  "config": { "version": 1, "preset": "developer", "enabled": ["docker"], "…": "…" },
  "network": { "mac": "52:54:00:…", "ip": "192.168.64.7", "reachable": true },
  "ssh": { "user": "opencodebar", "keyPath": "/…/ssh/id_ed25519", "publicKey": "ssh-ed25519 …" },
  "metrics": { "collectedAt": 1792900000000, "host": { … }, "guest": { … } }
}
```

`PATCH` accepts `name`, `cpuCount` (stopped only), `memoryMB` (stopped only),
`packages`, and `config`. Replacing packages or the builder config while the
guest is running queues an apply. The action routes are `POST` with an optional
`force` body or `?force=1`:

| Action | Notes |
| --- | --- |
| `start` | Boots the helper and waits for Virtualization.framework |
| `stop` | Graceful request, forced after 30 seconds |
| `restart` | Stop then start |
| `pause` / `resume` | Pause or resume the VM |
| `rebuild` | Replaces the disk; `force` is required when a disk exists |
| `apply` | Runs `nixos-rebuild switch`; the guest must be running |

`GET /api/vms/{id}/log?type=build|serial|apply&tail=240` returns the tail of one
log:

```json
{ "data": { "type": "build", "path": "/…/build.log", "lines": ["…"], "bytes": 12345, "truncated": true } }
```

Connect to `/api/vms/{id}/console/socket` with the Bearer token to attach to the
guest's serial console. The helper sends the last 64 KiB of boot output first,
then streams raw bytes; text frames from the client are written to the guest's
serial port. There is no resize or cursor protocol. The route returns `409` when
the VM is not running and `501` when the hub build has no VM socket relay.

Errors use the normal envelope; validation failures return `400`/`409`,
a missing VM `404`, and helper failures `502`.

#### Host setup

`GET /api/vms/setup` returns the current or last setup job:

```json
{
  "data": {
    "step": "nix",
    "status": "running",
    "command": "curl -fsSL https://nixos.org/nix/install | sh -s -- --yes",
    "requiresAdmin": true,
    "startedAt": 1792900000000,
    "finishedAt": null,
    "exitCode": null,
    "error": null,
    "log": {
      "path": "/Users/you/.local/share/opencodebar/vms/setup/nix.log",
      "lines": ["downloading Nix…", "installing…"],
      "bytes": 1234,
      "truncated": false
    }
  }
}
```

Start one with `POST /api/vms/setup` and `{ "step": "nix" }` or
`{ "step": "helper" }`. Only one job runs at a time; `409` means one is already
running or the step is already satisfied. `POST /api/vms/setup/cancel` stops a
running job and marks it `cancelled`.

The Nix step opens Terminal.app on the Mac and runs the installer as the
logged-in user; the password stays in Terminal, and the hub only reads the
output log. (A GUI Terminal is required because macOS SIP blocks the installer's
`/etc/fstab` step from a non-GUI process.) The helper step runs `make vz-helper`
in the repository. The Linux builder is intentionally not a job: it is a
long-lived VM started from a terminal.

Setup output is retained after the job ends, including the captured
`darwin.linux-builder` console (that builder is a Nix build service, not an
OpenCodeBar guest, so it never appears in `/api/vms`). `GET /api/vms/setup/logs`
lists the current and rotated files:

```json
{
  "data": [
    { "step": "nix", "path": "/…/vms/setup/nix.log", "bytes": 21913, "modified": 1792905120000 },
    { "step": "nix", "path": "/…/vms/setup/nix-2026-10-25T11-29-07.log", "bytes": 21913, "modified": 1792905000000 }
  ]
}
```

Logs can include the literal `Password:` prompt printed by `sudo`, but never the
password itself: `sudo` reads it from the terminal with echo disabled.

`GET /api/vms/setup/log?step=nix|helper|builder&tail=240` returns the newest log
for that step, ANSI stripped:

```json
{
  "data": {
    "step": "nix",
    "path": "/…/vms/setup/nix.log",
    "lines": ["downloading Nix…", "…"],
    "bytes": 21913,
    "truncated": true
  }
}
```

### Remote desktop

The remote endpoints drive the ScreenCaptureKit helper used by the iOS app's
**Host → Remote** view. Build it with `make remote-host`; the hub finds it in
`.build/` or uses `OPENCODEBAR_REMOTE_HOST`. Set `OPENCODEBAR_REMOTE=0` to
disable the endpoints.

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/remote` | Helper status, displays, permissions, capture settings |
| `POST` | `/api/remote/configure` | Set `fps`, `quality`, `maxWidth`, or `displayID` |
| `POST` | `/api/remote/permissions` | Request `screenRecording` and/or `accessibility` |
| `GET` | `/api/remote/socket` | WebSocket for JPEG frames, status, and input |

`/api/remote` returns:

```json
{
  "data": {
    "available": true,
    "running": true,
    "viewers": 1,
    "version": "1.0.0",
    "screenRecording": true,
    "accessibility": false,
    "displays": [
      { "id": 1, "name": "Built-in Retina Display", "width": 1470, "height": 956, "scale": 2, "primary": true }
    ],
    "displayID": 1,
    "fps": 12,
    "quality": 0.6,
    "maxWidth": 1600,
    "streaming": true,
    "error": null
  }
}
```

Connect to `/api/remote/socket` with the Bearer token. The server sends:

- **Text** JSON messages: `{"type":"status","data":{…}}` for the status above,
  and `{"type":"log","level":"info","message":"…"}` for helper events.
- **Binary** frames. The first 15 bytes are `0x02`, `"RD"`, a big-endian
  sequence number, a millisecond timestamp, and the frame's width and height
  (both `UInt16`); the rest is a JPEG.

Client messages are JSON:

```json
{"type":"pointer","action":"down|up|drag|move","x":0.5,"y":0.5,"button":"left|right","clickCount":1}
{"type":"scroll","dx":0,"dy":-24,"x":0.5,"y":0.5}
{"type":"key","key":"escape","modifiers":["cmd"]}
{"type":"text","text":"hello"}
{"type":"configure","fps":8,"quality":0.45,"maxWidth":1280}
{"type":"permissions","screenRecording":true,"accessibility":true}
{"type":"status"}
```

Coordinates are normalized to the selected display. Keys use a small named
table (US layout); modifiers are `cmd`, `ctrl`, `opt`, and `shift`. The helper
requires Accessibility permission to post events.

### Terminal.app tabs

These endpoints expose tabs already open in Terminal.app on the hub host. macOS
does not provide the PTY master for an existing tab, so the hub uses macOS
automation: it reads the visible text and runs commands in the tab.

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/host-terminals` | Tabs open in Terminal.app |
| `GET` | `/api/host-terminals/{tty}` | One tab plus its text mirror |
| `POST` | `/api/host-terminals/{tty}/command` | Run a line in the tab |
| `POST` | `/api/host-terminals/{tty}/focus` | Bring the tab to the front |

The `{tty}` path value is the device name without `/dev/`, for example
`ttys001`. The list response is:

```json
{
  "data": [
    {
      "id": "ttys001",
      "tty": "/dev/ttys001",
      "app": "Terminal",
      "title": "Build",
      "busy": true,
      "processes": ["login", "-zsh", "npm"],
      "window": 3,
      "tab": 1
    }
  ]
}
```

`GET /api/host-terminals/{tty}` adds `contents`, a plain-text mirror of the
visible screen, and optionally `history` with `?history=1`. Details are read
live; the list is cached briefly.

Run a command with:

```json
{ "command": "npm run build" }
```

The command goes through Terminal's own `do script` automation, so it behaves
like typing the line and pressing Return in the existing tab. An empty command
presses Return. This is line-based, not a raw keystroke channel: `Ctrl-C`,
arrow keys, and full-screen redraws are not forwarded. The focus endpoint
activates Terminal.app and selects the matching window/tab.

All four endpoints require the hub Bearer token. The hub needs macOS Automation
permission to control Terminal.app; without it the hub returns `503` with a
message explaining which setting to enable. Only Terminal.app is supported;
iTerm2, Warp, and IDE-integrated terminals use different scripting models.

### Host files

The hub can browse the machine it runs on read-only. Paths must be absolute, or
start with `~`; symlinks are resolved before a file is opened. Hub and OpenCode
credential files are blocked from preview.

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/files?path=…` | List one folder |
| `GET` | `/api/files/content?path=…` | Text or image metadata and text content |
| `GET` | `/api/files/raw?path=…` | Raw file bytes (max 25 MB) |

A listing returns entries sorted directories-first with `name`, `path`, `kind`
(`directory`, `file`, `symlink`, `other`), `isDirectory`, size, modification
time, permissions, hidden flag, and symlink target. It also includes `parent`,
shortcut `roots`, and `total`/`truncated` when a very large folder is capped at
2,000 entries.

The content endpoint returns `kind` (`text`, `image`, or `binary`), mime type,
size, modification time, and up to 512 KB of text (`truncated` marks a longer
file). Images are fetched through the raw endpoint by the clients.

`eventThrottleMs` is the maximum frequency at which updates reach the apps:
events queued during the window are folded together (streamed text deltas are
merged, older copies of the same session event are dropped). `0` forwards every
event immediately. The hub clamps values to the reported bounds, applies the
change without a restart, and persists it for the next launch:

```bash
curl -X PATCH http://127.0.0.1:8787/api/settings \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"eventThrottleMs":500}'
```

`preventSleep` holds an idle-sleep assertion on the hub host so a sleeping Mac
does not drop the phone's connection. It is supported on macOS only; when the
hub runs elsewhere, `preventSleepSupported` is `false` and the value has no
effect. The display can still turn off. Both settings can be sent together, and
omitting one leaves it unchanged:

```bash
curl -X PATCH http://127.0.0.1:8787/api/settings \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"eventThrottleMs":500,"preventSleep":true}'
```

### Sessions

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/session` | List cached sessions |
| `POST` | `/api/session` | Create a session |
| `GET` | `/api/session/active` | Active session map |
| `GET` | `/api/session/{id}` | One session |
| `GET` | `/api/session/{id}/message` | Paged messages |
| `GET` | `/api/session/{id}/children` | Child sessions |
| `GET` | `/api/session/{id}/forks` | Sessions forked from this conversation |
| `GET` | `/api/session/{id}/changes` | File patches |
| `GET` | `/api/session/{id}/stats` | Derived session stats |
| `GET` | `/api/session/{id}/git` | Repository state and commits made during the session |
| `GET` | `/api/session/{id}/pending` | Prompts admitted but not delivered |
| `DELETE` | `/api/session/{id}/pending/{inputID}` | Withdraw one queued prompt |
| `POST` | `/api/session/{id}/prompt` | Send a prompt |
| `POST` | `/api/session/{id}/pause` | Interrupt and hold until a time |
| `POST` | `/api/session/{id}/stop` | Interrupt and hold until continued |
| `POST` | `/api/session/{id}/continue` | Clear the hold and send `continue` |

`GET /api/session` query parameters:

| Parameter | Default | Values |
| --- | --- | --- |
| `limit` | `60` | 1–5000 |
| `offset` | `0` | 0–1,000,000 |
| `project` | — | Project id |
| `parentID` | — | Parent session id |
| `active` | `false` | `true` |
| `order` | `desc` | `asc` / `desc` |
| `q` | — | Search text |

A session forked with `POST /api/session/{id}/fork` carries a `fork` object:
`fork.sessionID` is the source conversation and `fork.boundary` describes where
the history was cut (`type` is `before` or `through`, plus `messageID`). The
source session lists its forks through `GET /api/session/{id}/forks`, newest
first. The relationship is cached, so it survives restarts and service
restarts.

`GET /api/session/{id}/message` supports `limit` (default 100, max 500) and
`cursor` from the previous response. Pass `since=<milliseconds>` to ask for only
the messages created or updated at/after that timestamp; the response is a delta
and has no cursor.

Create a session:

```bash
curl -X POST http://127.0.0.1:8787/api/session \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Fix the build","location":{"directory":"/Users/me/project"}}'
```

`location.directory` is required. `title` is optional; OpenCode can name the
session from the first message.

Send a prompt:

```bash
curl -X POST http://127.0.0.1:8787/api/session/$SESSION_ID/prompt \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"Run the test suite","delivery":"queue"}'
```

`delivery` is optional: `queue` waits for the current turn, `steer` asks the
service to steer the running turn. When omitted, the hub decides.

`GET /api/session/{id}/pending` returns the inputs the service has admitted but
not delivered yet, oldest first. Each item has `id`, `type`, `time.created`,
`delivery`, and a `payload` (user prompts carry `payload.text`). The queue lives
in the OpenCode service, so it is empty when the service is offline. Use
`DELETE /api/session/{id}/pending/{inputID}` to remove an item that has not
started; the hub answers `204`, and removes are a no-op once the turn has read
the prompt.

Pause a session until a time:

```bash
curl -X POST http://127.0.0.1:8787/api/session/$SESSION_ID/pause \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"forMs":1800000}'
```

Provide either `forMs` (a duration from now, at most 30 days) or `until` (epoch
milliseconds). The hub interrupts the active turn and returns the session with a
`control` object. `control.state` is `paused`; `control.at` is when the user
paused it and `control.until` is when it will continue. A held session is
excluded from `/api/session?active=true` and from the apps' Running list.

`POST /api/session/{id}/stop` takes no body and returns the session with
`control.state` set to `stopped` and no `until`. It waits indefinitely.
`POST /api/session/{id}/continue` clears the control and sends the literal
prompt `continue` into the conversation, then marks the session active. Sending
any other prompt also clears the control.

The hub checks timed pauses on every fast poll, so a pause fires even after a
hub restart. If OpenCode is offline when the deadline passes, the pause stays
and the hub retries on the next loop. A deleted session releases its control.

### Projects

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/project` | All projects |
| `GET` | `/api/project/{id}` | One project |
| `GET` | `/api/project/{id}/changes` | Aggregated project changes |
| `GET` | `/api/project/{id}/files` | Project files with git status |
| `GET` | `/api/project/{id}/git` | Full repository graph, branches, and tags |
| `GET` | `/api/project/{id}/icon` | The project's own app icon |

`/api/project/{id}/changes` accepts `sessions` (default 10, max 100) for how
many newer sessions to hydrate.

`/api/project/{id}/files` reads the project folder on the hub's machine. When
the folder is a git work tree, tracked and untracked-but-not-ignored files are
listed and working-tree changes are marked:

```json
{
  "data": {
    "files": [
      { "path": "README.md" },
      { "path": "Sources/App.swift", "status": "modified" },
      { "path": "Sources/New.swift", "status": "added" },
      { "path": "Sources/Old.swift", "status": "deleted" }
    ],
    "vcs": "git",
    "changed": 3,
    "total": 4,
    "truncated": false
  }
}
```

`status` is one of `added`, `modified`, `deleted`, or `renamed`. Without git,
`vcs` is `null` and no statuses are returned. Responses are capped at 20,000
entries; `truncated` marks a shortened list.

`/api/project/{id}/git` returns the full graph the project's Git tab draws.
`data` is `null` when the folder is not a work tree. Each commit carries its
parents and ref decorations, so clients can reconstruct merges and side
branches. `limit` defaults to 2,000 and accepts up to 20,000 commits; `total`
reports the full reachable count and `truncated` marks a shortened response.

```json
{
  "data": {
    "root": "/Users/me/project",
    "branch": "main",
    "head": {
      "hash": "4a45e54b…",
      "shortHash": "4a45e54",
      "parents": ["f1830e3…"],
      "author": { "name": "Ada", "email": "ada@example.com", "time": 1790000000000 },
      "committer": { "name": "Ada", "email": "ada@example.com", "time": 1790000000000 },
      "subject": "Add repository graph",
      "refs": ["HEAD -> main", "origin/main"]
    },
    "dirty": 2,
    "ahead": 1,
    "behind": 0,
    "branches": [
      { "name": "main", "hash": "4a45e54…", "current": true, "upstream": "origin/main", "ahead": 1, "behind": 0 }
    ],
    "tags": ["v1.0"],
    "commits": [],
    "total": 128,
    "truncated": false
  }
}
```

`/api/session/{id}/git` uses the same repository summary and adds the commits
made while the session was active. It never fails for a non-repository
directory; `repository` is `null` and `commits` is empty.

### Stats and usage

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/experimental/session/stats` | Global stats, optional `project` |
| `GET` | `/api/usage` | Go plan windows and cached usage |
| `GET` | `/api/search?q=…&limit=…` | Search sessions |
| `GET` | `/api/sync` | Incremental session/project feed |
| `POST` | `/api/sync` | Force a sync |
| `POST` | `/api/server/restart` | Restart the hub process |

### Incremental sync

`GET /api/sync` is the feed the iOS app uses instead of re-reading every
session and project on each poll. Without `since` it returns a full snapshot;
with `since=<revision>` it returns only the rows that changed after that
revision:

```json
{
  "revision": 4821,
  "full": false,
  "sessions": [{ "id": "ses_…", "time": { "updated": 1760000000000 } }],
  "deletedSessions": [],
  "projects": [],
  "deletedProjects": ["prj_old"],
  "active": ["ses_…"]
}
```

Clients keep `revision` and send it back on the next request. `full: true` means
the client must replace its local copy rather than merge; this happens on the
first request, when the client's revision is ahead of a reset hub, or when it
falls behind the retained change window. The active list is always sent in full.
No-op polls are not logged, so a quiet hub returns empty arrays and the same
revision.

### Events

`GET /api/event` is a Server-Sent Events stream. It sends `retry: 2000`, a
`data:` JSON event for each OpenCode/hub update, and a `: ping` comment every 15
seconds. Updates are batched according to the hub's `eventThrottleMs` setting
(see `/api/settings`): pending events of the same kind are folded into one
delivery per window, and streamed text/reasoning deltas keep their combined
text.

```bash
curl -N -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8787/api/event
```

The stream does not replay missed events. Reconnect and catch up with the
incremental `GET /api/sync` feed (then read the cached endpoints for details);
the hub rebuilds live activity from the newest messages when needed.

## Session stats shape

`/api/session/{id}/stats` returns derived data:

```json
{
  "data": {
    "sessionID": "ses_…",
    "prompts": 9,
    "steps": 159,
    "subagents": 0,
    "messages": 168,
    "tokens": { "input": 0, "output": 0, "reasoning": 0, "cache": { "read": 0, "write": 0 } },
    "cost": 0.34,
    "tools": { "mode": "detail", "totals": {}, "usage": [] },
    "failures": [],
    "files": { "files": 13, "additions": 223, "deletions": 90 },
    "complete": true
  }
}
```

The exact shape follows the shared Swift models and OpenCode payloads; treat
unknown fields as optional.

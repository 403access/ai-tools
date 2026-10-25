# OpenCodeBar

Watch your [OpenCode](https://opencode.ai) work from a native macOS app — in the
menu bar, in an optional desktop window, or from an iPhone/iPad app. Both talk
to **OpenCodeBar Hub**, a small Bun + SQLite server that ingests your local
OpenCode service and keeps one shared, cached history — so the phone can see
the Mac's sessions, projects, and usage.

📚 **Documentation:** <https://403access.github.io/ai-tools/docs/>

On macOS the menu bar item displays a terminal glyph and, when sessions are
running, the number of active sessions. **Left-click** it for the full desktop
app — a resizable window with a persistent sidebar — or **right-click** (or
control-click) for the compact panel with **live** activity, a full **session**
view, per-project **analytics**, and a **usage** overview. The desktop window
can also be turned on from **Settings → App → Desktop window** and is
remembered across launches. The iOS app has the same five areas — Live,
Projects, Usage, Host, and Settings — adapted for touch, with the same dark
panel design and a floating tab dock. **Host** switches between the System
inventory and Remote desktop, so the phone can also watch and control the Mac's
screen. Its Appearance setting can follow the system or stay dark/light. Both
apps can also start a new session, send a prompt into an open conversation, and
open terminals on the Mac to type into them. On iOS, **Live** and
**Usage** Home Screen widgets bring the same status to the Home Screen in
small, medium, and large sizes.

macOS panel:

![Live tab](docs/screenshots/live.png)
![Session detail](docs/screenshots/session.png)
![Session stats](docs/screenshots/stats.png)
![Session changes](docs/screenshots/changes.png)
![Prompts view](docs/screenshots/prompts.png)
![Projects tab](docs/screenshots/projects.png)
![Project detail](docs/screenshots/project-detail.png)
![Usage tab](docs/screenshots/usage.png)

iOS app:

![iOS live](docs/screenshots/ios-live.png)
![iOS session](docs/screenshots/ios-session.png)
![iOS projects](docs/screenshots/ios-projects.png)
![iOS usage](docs/screenshots/ios-usage.png)

## Features

**Desktop window (macOS)**
- Left-click the menu bar icon to run OpenCodeBar as a regular desktop app
  alongside the menu bar item. The resizable window has a persistent sidebar,
  shares live state with the compact panel, gets a Dock icon, and comes to the
  front when the icon is clicked again.
- On wide windows the list stays visible beside the detail page: projects sit
  next to their project page, and a session opened from a project adds a third
  column. Narrow windows fall back to the single-page layout.
- The window remembers its size and position. Right-click (or control-click)
  the menu bar icon for the compact tray panel.
- The window can also be toggled from **Settings → App → Desktop window** and
  is remembered across launches. Closing the window returns to menu-bar-only
  mode; left-clicking the icon opens it again.

**Live**
- Running sessions update in real time via OpenCode's SSE event stream, with new
  rows animating in at the top. Each row shows what the session is doing right
  now — the current tool and its command or path, streaming reasoning, todo
  progress, and the number of running subagents — alongside a pulsing indicator,
  project, model, agent, live cost, elapsed time, and token count.
- Recent sessions with project, model, relative time, cost, and tokens. Filter
  the list by project and by date (all time, today, last 7 days, or last 30
  days), or group it by day (today, yesterday, previous 7 days, and so on).
- Click any session to open its details: the full conversation with the newest
  message first, a prompts-only list with copy buttons, and expandable reasoning
  and tool calls. The view keeps updating while the session runs and pages back
  through history.
- **Reply from the conversation.** The composer at the bottom of the Chat tab
  sends a prompt into that session. A running session queues the message until
  the current turn finishes, and the conversation refreshes as it arrives.
  Queued prompts stay visible above the composer, with an **×** to withdraw one
  before the turn claims it.
- **Speak your prompt.** The microphone in the conversation composer and the
  new-session sheet turns speech into text as you talk. It keeps whatever you
  already typed, and the transcript stays editable before you send. Speech
  recognition runs on the device when the current language supports it.
- **Start a new session** from the Live tab or a project page: choose a project
  directory, an optional title, and an optional first message. The new session
  opens immediately, and the first message is sent in the same step.
- **Stats** tab: prompts, steps, tool-call reliability, per-tool failure counts
  and median durations, the recent failures with their errors, file impact, and
  the token mix for that session.
- **Changes** tab: every file the session wrote, with the actual patch, added
  and removed line counts, and a colour-coded diff. Repeated edits to one file
  are grouped, and long patches collapse to a preview. The layout button swaps
  the diff cards for a collapsible file tree; tap a file to see its patch. Tool
  cards in the conversation show the same diff instead of raw edit JSON.
- Subagent tree: a session's direct child sessions appear in a **Subagents** tab
  with their own live activity, outcome, cost, and time. Tap one to drill in;
  Back returns to the parent, and each level loads its own children.

**Home Screen widgets (iOS)**
- **Live** shows the running-session count and what each session is doing now,
  with elapsed timers, project, current tool or activity, cost, and tokens.
  Small shows the count and top session; medium shows two running rows; large
  adds more running rows plus recent sessions.
- **Usage** shows today's steps, cost, tokens, streak, prompts, and tool calls,
  the last 14 days of activity, and Go plan-limit bars with reset countdowns.
- Both adapt to small, medium, and large families and open the matching tab when
  tapped.
- Widgets fetch the hub directly and fall back to their last snapshot, so they
  keep showing useful data while the app is closed or the hub is offline.
  Pairing details are shared through a keychain access group.

**Projects**
- Every project OpenCode has run in, with running work first and the most
  recently active next. Each row shows the icon the project already ships with:
  an Xcode **AppIcon** asset, an `.icns` bundle, an Apple touch icon, favicon,
  or logo. Folders with no artwork keep a folder glyph.
- Select one to open its detail page: the project name, path, and quick actions
  stay pinned while tabs keep each kind of content on its own screen.
- **Overview** shows what is running right now — with elapsed time, tappable into
  the session view — plus at-a-glance steps, cost, tool calls, failures, tokens,
  and streak, followed by the six most recent sessions.
- **Stats** has the scoped trend and model mix, plus tool reliability for the
  project: total calls and per-tool succeeded, failed, and unfinished counts with
  median durations. The trend is an interactive daily chart for steps, cost, or
  tokens over the last 30 / 90 / 365 days or all time, using only that project's
  data.
- **Changes** aggregates the patches written by the project's newest sessions,
  grouped by session and file. **Files** lists every file in the project folder,
  including untracked files, and marks git working-tree changes as added,
  modified, or deleted; filter it to changed files or search by path. The layout
  button swaps the flat list for a collapsible folder tree.
- **Sessions** lists every session in the project with its cost and time,
  revealed in pages of 50. Quick actions open the project in Finder or Terminal
  and copy its path.
- Duplicate records for the same directory are merged, and analytics are
  fetched per project from the stats API rather than derived from the session
  list.

**Usage**
- OpenCode Go plan limits: rolling (5h), weekly, and monthly consumption as
  percentage bars with reset countdowns, read from the Go usage API. Hidden
  when no Go key is configured.
- Usage numbers and plan limits are cached on disk, so the tab keeps showing the
  last known values — flagged as stale — when the service or the API is
  unreachable.
- Summary tiles: streak, active days, today's steps, prompts, sessions, total
  cost, tokens, tool calls, and subagents.
- An interactive daily trend chart for steps, cost, or tokens across the last
  30 / 90 / 365 days or all time.
- Top projects by cost, with the same selectable windows.
- A GitHub-style activity heatmap of daily agent steps.
- Token mix (input / output / reasoning / cache read / cache write).
- Per-model breakdown with steps and cost.
- Tool call success/failure summary.

**System**
- A full inventory of the machine running the hub: macOS / Linux / Windows
  identification, distribution or macOS release, kernel, architecture, model,
  chip, boot time, timezone, locale, user, and shell.
- Live CPU usage overall and per core, load averages, physical/logical cores,
  clock speed, thermal pressure, and temperatures where the platform exposes
  them. Memory totals, active/wired/compressed pages, available memory, and swap.
- Every mounted volume with filesystem, capacity, and free space. Network
  interfaces with IPv4/IPv6 addresses and MACs, default gateway, DNS servers, and
  listening TCP ports with their owning process.
- Battery percentage, state, health, cycle count, condition, and temperature;
  SIP, FileVault, firewall, Gatekeeper, SELinux/AppArmor, and Defender status.
- Top processes by CPU or memory, with PID, user, and resident size.
- Installed applications discovered from the OS (with versions, bundle ids,
  sources, and paths) and a searchable filter.
- Homebrew version, prefix, formula/cask counts, outdated markers, and the full
  package list with versions.
- Developer runtimes and tools (Node, Bun, Python, Go, Rust, Java, Swift, Docker,
  Git, and more), Docker containers, GPUs and displays, plus the hub process's
  own PID, uptime, memory, port, and database size.
- **Now playing**: title, artist, album, elapsed time, duration, playback state,
  audio/video kind, and the app that owns the session. macOS MediaRemote covers
  Music, Spotify, browsers, and other players, while audio/video assertions catch
  apps that play without publishing metadata.
- **Media controls**: play/pause, previous/next, 15-second skip where the player
  supports it, mute, and a system output-volume slider. Commands target the
  current system player; available buttons are driven by the player's own
  supported-command list.
- **Terminals**: every pseudo-terminal OpenCode knows about, across all of its
  project locations — including terminals opened from OpenCode's own terminal
  panel. Each row shows the shell, working directory, location, PID, and whether
  it is running or exited. Tap one to open a full terminal emulator and type
  into it, or start a new shell in any project and stop terminals you no longer
  need. The hub proxies the PTY socket, so the same terminals work from the
  iPhone/iPad app over the LAN or a tunnel.
- **Terminal.app tabs**: tabs already open in Terminal.app on the hub host are
  listed separately. Open one to see a live text mirror of its screen and run
  commands in the existing tab. This uses macOS Automation, so the hub needs
  permission to control Terminal.app. It is line-based (type a command and
  press Return), not a byte-for-byte PTY stream.
- **Host file browser**: browse any folder on the server read-only, with
  breadcrumbs, quick links to Home, Root, Applications, Volumes, and project
  folders, hidden-file toggle, search, and text/image previews. Hub and OpenCode
  credential files are excluded from previews.
- Polls every five seconds; expensive inventory scans are cached by the hub so
  the panel stays responsive.

**Remote desktop (iOS)**
- The **Host → Remote** segment streams the Mac's display to the phone over the
  hub and sends taps, drags, scrolling, and keyboard input back. Pinch to zoom,
  two-finger pan, and a two-finger tap toggles between fit and zoomed; the
  toolbar has modifier chips and Escape, Tab, Delete, Return, and arrow keys.
- A small ScreenCaptureKit helper captures one display as JPEG over the same
  authenticated WebSocket. **Sharp**, **Balanced**, and **Fast** quality presets
  trade resolution and frame rate for Wi-Fi or a tunnel, and the status strip
  shows the measured frame rate.
- Screen Recording and Accessibility permissions are required on the Mac (the
  app links straight to the request). Without Accessibility the stream is
  view-only. `make hub` builds the helper; `make remote-host` rebuilds it alone.

**Settings**
- Every app connected to the hub — macOS, iOS, and iPadOS — with its device
  name, platform, app version, and whether it is live right now. Click a device
  for its stable ID, first and last seen timestamps, and live connection state.
- Server information: hub version, address, uptime, cached session/message
  counts, OpenCode state, last sync, and the SQLite path.
- Server controls: sync now, restart the hub, reveal its data/config files, and
  refresh. Pairing shows a scannable QR code plus the copyable link for adding
  another phone.
- **Power**: choose whether the Mac may sleep while the hub runs. Keeping it
  awake holds an idle-sleep assertion so phones and tablets keep their
  connection; the display can still turn off. The preference is stored by the
  hub and applied again after a restart.

**iPhone & iPad**
- The same Live, Projects, Usage, Host, and Settings areas as the Mac panel,
  with the same compact panel design, live-activity folding, and a floating tab
  dock built for touch. **Host** has a System/Remote switch: System mirrors the
  Mac's full machine inventory, so the phone can monitor CPU, memory, disks,
  processes, Homebrew, and installed apps without the Mac app being open — and
  browse the Mac's files with the same read-only browser. Remote streams and
  controls the Mac's display with touch and keyboard input.
- Search projects, pull to refresh any screen, and open a session from a deep
  link. Settings shows hub and OpenCode health, cached session/message counts,
  uptime, last sync, and a **Keep Mac awake** switch for the host Mac.
- A local SQLite cache renders the last snapshot on launch, then asks the hub
  for changes only (`/api/sync?since=…`) instead of re-reading every session and
  project on each poll. Opened sessions keep their newest messages on device too.
- Appearance can follow the system or stay dark or light.
- Pair by scanning the QR code in the Mac app's Settings tab, pasting the hub
  URL and token, or the `opencodebar://pair?url=…&token=…` link the hub prints;
  the token is stored only on the device.

**Shared hub**
- One Bun + SQLite server ingests OpenCode once and serves both apps behind a
  Bearer token. Sessions, messages, file changes, stats, and Go plan limits are
  cached in `~/.local/share/opencodebar/hub.sqlite`, so the iOS app — and the Mac
  app when OpenCode is stopped — still show history and last-known numbers.
- The hub discovers the local service, polls read endpoints, forwards the SSE
  stream, and forwards prompts and new-session requests back to OpenCode. A
  configurable throttle folds rapid updates before sending them to the apps, so
  busy sessions do not flood the connection.

Both apps can start sessions and send prompts; neither stops or deletes
sessions. Both can also list and drive terminals on the hub host.

## How it works

OpenCode runs a client-server architecture. Interfaces such as the TUI talk to a
background service that listens on loopback and is protected by HTTP Basic auth.

OpenCodeBar Hub sits between that service and the apps:

```
OpenCode service (loopback, Basic auth)
          │  REST + SSE
          ▼
OpenCodeBar Hub (Bun + SQLite, Bearer auth)
          │  cached REST + SSE, mirrored shapes
    ┌─────┴─────┐
    ▼           ▼
 macOS app   iOS app
```

The hub:

1. Discovers the local OpenCode service the same way the old app did — the
   password from `~/.config/opencode/service.json`
   (or `$XDG_CONFIG_HOME/opencode/service.json`), the URL from
   `opencode service status`, then `lsof`, then the server log.
2. Polls read endpoints on a 5s / 60s cadence, subscribes to `/api/event`,
   and writes sessions, projects, messages, stats, and Go plan usage into
   `~/.local/share/opencodebar/hub.sqlite`. The cache keeps serving when OpenCode
   stops or restarts on a new port. Writes from the apps — creating a session
   and prompting one — are forwarded to the same service.
3. Serves a stable API that mirrors OpenCode's shapes — `/api/session`,
   `/api/session/{id}`, `/api/session/{id}/message`, `/api/session/{id}/changes`,
   `/api/session/{id}/stats`, `/api/project`, `/api/project/{id}/changes`,
   `/api/project/{id}/files`, `/api/project/{id}/icon`,
   `/api/experimental/session/stats` — plus
   `/api/session/{id}/prompt` (`POST`), `/api/session` (`POST`), `/api/usage`,
   `/api/health`, `/api/system`, `/api/terminals` (`GET`/`POST`),
   `/api/terminals/{id}` (`GET`/`PUT`/`DELETE`),
   `/api/terminals/{id}/socket` (WebSocket), `/api/host-terminals`,
   `/api/host-terminals/{id}`, `/api/host-terminals/{id}/command`,
   `/api/host-terminals/{id}/focus`, `/api/files`, `/api/files/content`,
   `/api/files/raw`, `/api/devices`,
   `/api/settings` (`GET`/`PATCH`), `/api/sync` (`GET` delta feed, `POST` force
   sync), `/api/server/restart` (`POST`), and `/api/event`. Clients
   authenticate with a Bearer token and identify their platform with
   `X-OpenCodeBar-*` headers so the settings screen can list connected devices.
4. Forwards OpenCode events to every connected client, so both apps update live.
   Rapid updates are coalesced into a configurable window (`eventThrottleMs`,
   250 ms by default) before delivery. The stream also carries `hub.*` notices
   (`hub.connected`, `hub.sessions`, `hub.stats`, `hub.usage`) that tell clients
   when cached data changed.

Endpoints the hub reads from OpenCode: `/api/info`, `/api/session`,
`/api/session/active`, `/api/session/{id}`, `/api/session/{id}/message`,
`/api/project`, `/api/experimental/session/stats`, `/api/pty`, and
`/api/event`. It writes through `POST /api/session`,
`POST /api/session/{id}/prompt`, and the PTY create/update/delete routes. Each
terminal WebSocket is proxied to `/api/pty/{id}/connect`; the hub opens that
upstream socket with OpenCode's Basic credentials so clients only need the hub
token.

The event stream does more than trigger refreshes. `session.step.*`,
`session.reasoning.*`, `session.text.*`, `session.tool.*`, `session.usage.*`,
and `permission.*` events are folded into a per-session activity snapshot, which
is what the Live rows show. Cost and token counts move as `session.usage.updated`
arrives instead of waiting for the next poll. When the stream is missed — on
launch or after a reconnect — the newest messages are read back to rebuild the
snapshot, including the latest `todowrite` list. Both apps fold events the same
way from the shared payloads.

The trend charts use the stats API's daily activity for steps, and group the
full session list by day for cost and tokens (the iOS app reuses its local
session cache; the Mac fetches `/api/session?limit=1000` on the slow cycle).
Project pages use the same series scoped to that project.
Message history is cached the first time a session is opened, so paging back
through it works offline. The Changes views read the `metadata.files` patches
that OpenCode attaches to edit/write tool calls; the hub extracts them while
caching messages, so patches survive an OpenCode restart. Opening a session's
Changes tab hydrates its full history the first time; project changes hydrate
the newest 10 sessions (adjustable with `?sessions=`) and always include any
older changes already cached.

Tool reliability comes from two places. Project and usage breakdowns ask the
stats API for `tools=detail`, which adds per-tool succeeded/failed/unfinished
counts and median durations. Sessions have no stats endpoint upstream, so the
hub derives their numbers from cached messages: tool parts are indexed by name
and outcome when a message is cached, and the first `/api/session/{id}/stats`
request pages through up to 30 pages of history. The response says whether the
history is complete, and the Stats tab notes when totals cover only the loaded
window.

### Connecting the apps

The hub writes its URL and token to `~/.config/opencode/opencodebar-hub.json`
(owner-only) when it starts, so the Mac app connects with no configuration. The
iOS app pairs by scanning the QR code in the Mac app's Settings tab, or by
pasting that URL and token, or the `opencodebar://pair?url=…&token=…` link the
hub prints. The QR code uses the Mac's LAN address (or a running
`make hub-tunnel` URL) so the phone can reach the hub. Overrides:

1. `$OPENCODEBAR_HUB_URL` / `$OPENCODEBAR_HUB_TOKEN`
2. `hubURL` / `hubToken` in `~/.config/opencode/opencodebar.json`
3. the generated `opencodebar-hub.json`

On cellular, or on any network where the Mac is not directly reachable, start a
tunnel in a second terminal:

```sh
make hub-tunnel     # Cloudflare quick tunnel, no account needed
```

It prints a public HTTPS URL and a fresh pairing link, and writes
`~/.config/opencode/opencodebar-hub-tunnel.json` while it runs. `make
mobile-device` picks that URL up automatically, and the Mac app's pairing QR
code uses it too. Every request still needs the hub token. For a stable address,
run Tailscale on both devices and pair with the Mac's Tailscale IP instead.

For Go plan limits the hub calls the console's usage endpoint,
`https://opencode.ai/zen/go/v1/usage`, and caches the result for both apps. The
key is resolved in this order:

1. `$OPENCODE_GO_USAGE_KEY`
2. `$OPENCODE_API_KEY`
3. `goUsageKey` in `~/.config/opencode/opencodebar.json`
4. the `opencode-go` (then `opencode`) key in `~/.local/share/opencode/auth.json`

Step 3 exists so a read-only or service-account key can be used for usage
without replacing the credential OpenCode uses for inference.

## Requirements

- macOS 14 (Sonoma) or later for the menu bar app.
- iOS 17 or later for the mobile app (simulator or device).
- [Bun](https://bun.sh) 1.1+ for the hub, and Xcode or the Swift toolchain
  (`swift` on your `PATH`) for the Mac app.
- Xcode with the iOS simulator, plus [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  (`brew install xcodegen`), to build the iOS app.
- To run the iOS app on a physical device, an Apple ID signed into Xcode with a
  development team, and Developer Mode enabled on the device.
- OpenCode V2 running as the background service (`opencode service status`
  prints a URL).
- Node.js 20+ to build the Docusaurus documentation site.
- The terminal views use [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
  (MIT). SwiftPM and Xcode fetch it automatically on the first build.

## Build and run

```sh
# 1. Start the hub. The first run generates a token and prints the URL,
#    LAN address, and a pairing link for the phone.
make hub

# 2. Build and launch the macOS menu bar app.
make run

# 3. Build, install, and launch the iOS app in a simulator, paired with the hub.
make mobile-run

# ... or on a connected iPhone/iPad (signing required).
make mobile-device
```

```sh
make run        # build dist/OpenCodeBar.app and launch it
make restart    # rebuild and restart the running app
```

`make restart` runs `Scripts/restart.sh`, which builds first and only then
stops the old instance — so a failed build leaves the current app running.
The script can also be called directly:

```sh
Scripts/restart.sh --no-build      # relaunch the existing bundle
CONFIG=debug Scripts/restart.sh    # rebuild a debug bundle instead
```

Other targets:

```sh
make build         # swift build (debug)
make test          # swift test
make bench         # shared-code performance microbenchmarks
make app           # assemble dist/OpenCodeBar.app (release)
make preview       # open the panel in a normal window for design work
make shots         # regenerate docs/screenshots
make icon          # regenerate the app icon
make hub           # run the SQLite sync hub (foreground)
make hub-dev       # hub with auto-reload
make hub-test      # hub unit tests (Bun)
make hub-tunnel    # expose the hub through a Cloudflare quick tunnel
make remote-host   # build the ScreenCaptureKit remote-desktop helper
make mobile-build  # build the iOS app and widget extension for the simulator
make mobile-run    # build, install, launch, and pair the iOS app in a simulator
make mobile-device # the same on a connected iPhone/iPad
make docs          # run the Docusaurus docs site locally
make docs-build    # build the docs for production
make docs-serve    # build and serve the docs locally
make clean         # remove build artifacts and dist/
```

`make mobile-device` builds with the team currently selected in Xcode, falling
back to the team on your Apple Development certificate; set `DEVELOPMENT_TEAM=…`
to choose another team. If more than one phone is connected, pick one with
`DEVICE="iPhone von Oli"` (name, UDID, or serial number). The script reuses the
hub's token and pairs over the Mac's LAN address when the phone is on the same
Wi-Fi, or over a running `make hub-tunnel` URL when one is available. That
second case is what makes the app work on cellular — including while the Mac is
tethered through the phone's hotspot, where iOS does not route back to the Mac.
It all happens in one step:

```sh
make mobile-device DEVICE="iPhone von Oli"

Scripts/run-mobile-device.sh --no-build   # reinstall the last build
Scripts/run-mobile-device.sh --console    # stream the app's log output
```

On the first run, connect and unlock the device, tap **Trust**, and enable
**Settings → Privacy & Security → Developer Mode**.

Remote desktop needs two macOS privacy grants for the capture helper. `make hub`
builds the helper automatically (or run `make remote-host` yourself), then open
**Host → Remote** on the phone and tap **Allow** on the permission card:

- **Screen Recording** lets the helper capture the display. Without it the
  Remote screen stays black and explains what is missing.
- **Accessibility** lets the helper post pointer and keyboard events. Without it
  you can still watch the screen, but the app shows **View only**.

The prompt appears on the Mac. If it does not, add the helper in **System
Settings → Privacy & Security → Screen Recording / Accessibility** and restart
the hub. The helper is `.build/debug/OpenCodeBarRemoteHost` during development;
override the path with `OPENCODEBAR_REMOTE_HOST=/path/to/helper` or disable the
feature entirely with `OPENCODEBAR_REMOTE=0`.

The first Mac build generates `Assets/AppIcon.icns` and ad-hoc signs the bundle.

To launch the Mac app at login, add `dist/OpenCodeBar.app` in **System Settings →
General → Login Items**. The hub can run as a launch agent if you want the phone
to reach it without starting a terminal.

## Website and docs

The project has two published surfaces:

- [`docs/`](docs/index.html) — the static marketing page. Plain HTML/CSS with a
  small progressive-enhancement script; no build step.
- [`website/`](website/) — a Docusaurus 3 documentation site with guides, an API
  reference, configuration, development notes, and troubleshooting.

```sh
make site         # open the marketing page
make docs         # run the docs site locally (hot reload)
make docs-build   # production docs build
make docs-serve   # build and serve the production docs
```

The docs dev server runs at `http://localhost:3000/ai-tools/docs/`, matching the
published base path.

### GitHub Pages

`.github/workflows/deploy-pages.yml` builds both surfaces and deploys one
artifact:

```
/                     marketing page from docs/
/docs/                Docusaurus build from website/
```

In the repository, set **Settings → Pages → Build and deployment → Source:
GitHub Actions**. Pushes to `main` that touch `docs/`, `website/`, or the
workflow then publish:

- <https://403access.github.io/ai-tools/>
- <https://403access.github.io/ai-tools/docs/>

## Project layout

```
Sources/OpenCodeBar/          macOS menu bar app (SwiftPM)
  OpenCodeBarApp.swift      AppKit entry point, app delegate
  StatusItemController.swift    status item, left/right click routing, panel popover
  DesktopWindowController.swift  optional desktop window, Dock mode, app menu
  main.swift                entry point (also handles --preview)
  AppState.swift            observable state, polling, derived data
  AppState+Terminals.swift  terminal polling, creation and removal
  AppState+HostTerminals.swift  Terminal.app tab polling
  Core/
    HubAPI.swift            async client for the hub (shared with iOS)
    HubAPI+Endpoints.swift  endpoint methods
    HubAPI+Transport.swift  requests, decoding and diagnostics
    HubModels.swift         hub transport/health models
    HubEventStream.swift    SSE subscription with reconnect (shared)
    RemoteDesktopModels.swift  remote status, frame header, modifiers (shared)
    HubDiscovery.swift      reads the hub URL + token (macOS)
    ServiceDiscovery.swift  OpenCode config paths
    DeviceIdentity.swift    stable client id + platform headers (shared)
    WidgetShared.swift      shared keychain + widget snapshot cache
    UsageCache.swift        last-known usage on disk
    TerminalConnection.swift  terminal WebSocket, input and resize bridging (shared)
    HostTerminalMirror.swift  Terminal.app text mirror and command input (shared)
  Support/
    QRCode.swift            pairing QR rendering
  Models/                   Codable models, split by domain (shared)
    TokenUsage.swift        token/model primitives
    Session.swift           sessions and projects
    Stats.swift             aggregate and per-session statistics
    Messages.swift          messages, parts and pending prompts
    Changes.swift           file patches and grouping
    ProjectFiles.swift      project file browser payloads
    APIEnvelopes.swift      request/response envelopes
    OpenCodeEvent.swift     decoded event payloads (shared)
    ProjectOrdering.swift   project merge + ordering from running counts (shared)
    SessionActivity.swift   live "what is it doing" state (shared)
    SessionActivity+Events.swift  event folding
    SessionActivity+Derive.swift  rebuild from cached messages
    SubagentOrdering.swift  running-first ordering for child sessions
    SessionOrdering.swift   most-recent-first ordering for feeds
    WidgetSnapshot.swift    compact widget payload shared by app and extension
    SessionFilter.swift     project/date filters for recent feeds
    GoUsage.swift           Go plan windows (shared)
    SystemInfo.swift        machine inventory from the system endpoint (shared)
    Terminals.swift         OpenCode PTY sessions and requests (shared)
    HostTerminals.swift     Terminal.app tab models (shared)
    HostFiles.swift         host directory listings and previews (shared)
  Views/                    SwiftUI panel, tabs, heatmap, components
    DesktopView.swift       full-window layout with a persistent sidebar
    ChangeViews.swift       patch cards and change summaries
    NewSessionSheet.swift   start a session with an optional first prompt
    PerformanceViews.swift  skeleton placeholders and shimmer (shared)
    SessionDetailView.swift session header and tabs
    SessionDetailView+Composer.swift  pending queue and composer
    SessionDetailView+Content.swift   conversation/stats/changes/prompts
    SessionDetailView+Loading.swift   message paging
    SessionMessageViews.swift         message, part and prompt cards
    ProjectDetailView.swift           project header, tabs, and sections
    ProjectDetailAnalytics.swift      scoped at-a-glance stats
    ProjectSessions.swift             recent-session rows
    SettingsTab.swift       connected devices and server controls
    SystemTab.swift         machine, resources, apps, Homebrew and tools
    TerminalViews.swift     terminal list, new-terminal sheet and terminal window
    TerminalEmulatorView.swift  SwiftTerm host for Mac and iOS
    SystemFileBrowser.swift host folder navigation and text/image preview
    SettingsTab+Support.swift         derived labels and actions
    SettingsDeviceRow.swift           device row in the connected list
    SettingsDeviceDetail.swift        status, timestamps and identity for one device
    SessionStatsView.swift  per-session reliability and failures
    SubagentViews.swift     tap-through child-session tree
  Preview/PreviewRunner.swift

Sources/OpenCodeBarRemoteHost/  ScreenCaptureKit helper for remote desktop
  main.swift                stdio entry point, AppKit run loop
  RemoteHost.swift          capture, permissions, pointer/key board input
  Wire.swift                framed status/frame/log transport

Sources/OpenCodeBarMobile/    iOS app (XcodeGen target)
  OpenCodeBarMobileApp.swift  app entry + tab bar
  MobileStore.swift           observable state for the hub
  MobileStore+Sync.swift      snapshot/delta refresh
  MobileStore+Events.swift    event folding and activity seeding
  MobileStore+Messages.swift  messages and prompt queue
  MobileStore+Loaders.swift   project/changes/stats/subagent loaders
  MobileStore+Derived.swift   derived feeds
  MobileDatabase.swift        local SQLite cache + incremental sync
  MobileDatabase+Sessions.swift  sessions/projects persistence
  MobileDatabase+Messages.swift  message cache
  MobileDatabase+Metadata.swift  stats/usage/identity
  MobileDatabase+Schema.swift    schema migration
  HubSettings.swift           URL + token storage and pairing links
  MobileRouter.swift          widget/deep-link routing
  WidgetPublisher.swift       writes the shared widget snapshot
  PairingScanner.swift        camera QR scanner for pairing
  LiveView.swift              running/recent sessions
  LiveView+Filters.swift      project/date filters
  SessionDetailView.swift     conversation, stats, changes, prompts, subagents
  SessionDetailView+Header.swift    live summary
  SessionDetailView+Composer.swift  pending queue and composer
  SessionDetailView+Content.swift   tab content
  SessionDetailView+Pieces.swift    shared loading/error views
  SessionDetailView+Loading.swift   message paging
  NewSessionSheet.swift       start a session from the phone
  MobileMessageViews.swift    message cards
  MobileChangeViews.swift     patch cards and change summaries
  MobileSessionStatsView.swift  per-session reliability and failures
  ProjectsView.swift          project list + search
  ProjectDetailView.swift     scoped analytics and project changes
  UsageView.swift             plan limits, trends, stats
  SystemView.swift            machine inventory for the hub host
  HostView.swift              System/Remote switch for the Host tab
  RemoteDesktopView.swift     remote display, controls, permission cards
  RemoteDesktopSurface.swift  zoomable display view and touch gestures
  RemoteDesktopConnection.swift  frame WebSocket, decoding, pointer/key input
  MobileTerminalViews.swift   terminal list, new-terminal sheet and terminal sheet
  MobileStore+Terminals.swift terminal polling, creation and removal
  MobileStore+HostTerminals.swift Terminal.app tab polling
  MobileFileBrowser.swift     host folders and file previews
  MobileCharts.swift          Swift Charts trend cards
  SettingsView.swift          appearance, pairing, and status
  SettingsView+Connection.swift  status and hub connection controls
  MobileComponents.swift      shared mobile views
  MobileTheme.swift           dark design tokens and shared backgrounds

Sources/OpenCodeBarWidgets/   iOS Home Screen extension (XcodeGen target)
  OpenCodeBarWidgets.swift    WidgetBundle with Live and Usage
  LiveWidget.swift            running sessions, all three sizes
  UsageWidget.swift           stats, trend, plan limits, all three sizes
  WidgetDataLoader.swift      hub fetch + cached-snapshot fallback
  WidgetTheme.swift           widget palette and compact components

server/                       Bun + TypeScript + SQLite hub
  src/index.ts                entry point and startup output
  src/config.ts               env/config resolution, pairing link
  src/types.ts                wire types shared with the apps
  src/opencode.ts             OpenCode integration (barrel)
  src/opencode/               discovery, REST client, errors, Go usage
  src/terminals.ts            PTY aggregation and lifecycle across locations
  src/host-terminals.ts       Terminal.app tabs via macOS automation
  src/api/terminal-socket.ts  WebSocket proxy for live terminal input/output
  src/remote.ts               capture helper lifecycle and status
  src/api/remote-socket.ts    WebSocket fan-out for frames and input
  src/db.ts                   SQLite facade
  src/db/                     schema, row mapping, stores, queries
  src/hub.ts                  polling/event hub facade
  src/hub/                    event bus, sync, reads, usage cache
  src/files.ts                project file browser
  src/browser.ts              read-only host file browser and previews
  src/projectIcon.ts          project app icon discovery and rendering
  src/api.ts                  HTTP routes
  src/api/                    request helpers and SSE clients
  test/                       Bun tests for the database and API

website/                      Docusaurus documentation site
  docs/                       guides, API reference, configuration, help
  src/                        theme components and custom CSS
  static/img/                 docs logo and screenshots
  docusaurus.config.js        site config for /ai-tools/docs/
  sidebars.js                 documentation navigation

docs/                         static marketing site
  index.html
  assets/
  screenshots/                shared screenshots used by README and site

performance/                  performance analysis and results
  before.md                   baseline hot paths and measurements
  after.md                    implemented changes, results, follow-ups

.github/workflows/
  deploy-pages.yml            build marketing + docs, deploy GitHub Pages

project.yml                   XcodeGen spec for the iOS app + widgets
Mobile/Info.plist             generated by XcodeGen
Mobile/Widgets-Info.plist     generated by XcodeGen
Mobile/*.entitlements         shared keychain group for app + widget
Scripts/
  build-app.sh                assemble the macOS .app bundle
  restart.sh                  rebuild and restart the Mac app
  run-mobile.sh               install, launch, and pair the iOS app in a simulator
  run-mobile-device.sh        the same on a physical iPhone/iPad
  perf-benchmark.sh           compile and run the shared-code microbenchmarks
  PerfBenchmark.swift         synthetic data + measurements for the benchmark
  make-icon.swift             generate the app icon
Tests/OpenCodeBarTests/       Swift tests (event folding, ordering)
```

## Development notes

- The status item is created by hand (`StatusItemController`) rather than by a
  `MenuBarExtra` scene: left-click opens the desktop window, right-click opens
  the compact panel.
- `make desktop` builds the app and turns on the desktop window (`--desktop`).
  The saved preference lives in **Settings → App → Desktop window**; when it
  is on, the window opens on every launch and the app keeps a Dock icon.
  Closing the window switches back to menu-bar-only mode.
- `--preview` runs the panel in a regular window instead of the menu bar
  popover, which makes screenshots and layout iteration easy.
  `--preview --tab usage` opens the Usage tab directly.
- `--screenshot <path>` renders the panel offscreen to a PNG and exits.
  `--screenshot out.png --scale 2 --tab usage` produces a 2x image for the
  website and README. Add `--detail` (optionally `--detail-mode prompts`,
  `stats`, or `changes`) to render the session detail view, or
  `--project-detail` for the first project's detail page. `--session <id>` opens
  a specific session; combine it with `--detail-mode subagents` to inspect a
  session's child sessions. Add `--terminal` to render the first OpenCode
  terminal instead of the panel, or `--host-terminal` for the first Terminal.app
  mirror; both are handy for checking the terminal views. Stats and Changes
  hydrate history on the first request, so open those tabs once (or warm the hub
  cache) if a shot would otherwise capture the loading state.
- `OPENCODEBAR_DEBUG_SUBAGENTS=1` logs hub/subagent requests to stdout.
- The menu bar glyph uses SF Symbols (`terminal` / `terminal.fill`).
- iOS screenshot tooling (Debug builds): `OPENCODEBAR_TAB=live|projects|usage|settings`
  selects the starting tab, and `OPENCODEBAR_OPEN_SESSION=running` (or a session
  id) opens a session on launch. With `simctl`:
  `SIMCTL_CHILD_OPENCODEBAR_TAB=usage xcrun simctl launch booted dev.opencodebar.mobile`.
- Hub environment: `OPENCODEBAR_HUB_PORT` (default 8787),
  `OPENCODEBAR_HUB_HOST`, `OPENCODEBAR_HUB_DB`, `OPENCODEBAR_HUB_TOKEN`,
  `OPENCODEBAR_HUB_URL` (clients), `OPENCODEBAR_PREVENT_SLEEP` (`1` holds an
  idle-sleep assertion while the hub runs), `OPENCODEBAR_LOG_LEVEL`.
- `OPENCODE_GO_USAGE_URL` points the hub's Go limits client at a different URL,
  which is how the Plan limits UI is exercised without a live Go key.
- `OPENCODE_API_KEY` overrides the Go API key read from `auth.json`, and
  `OPENCODE_GO_USAGE_KEY` overrides both. GUI-launched builds may not inherit
  a shell environment, so `~/.config/opencode/opencodebar.json` is usually the
  more reliable place to keep a usage-only key.

## Limitations

- The Mac app needs macOS 14+; the mobile app needs iOS 17+. The hub is a Bun
  process that must be reachable over the network for the phone.
- The apps can start sessions and send prompts, but not interrupt, stop, or
  delete them. Prompts sent to a running session are queued behind the current
  turn.
- Terminal access runs commands as the same user as the hub and OpenCode. The
  hub token protects it, but anyone with the token can run anything that user
  can. Keep the token private and use a trusted network or a tunnel.
- Terminal.app tabs are read and controlled through macOS Automation. The hub
  needs permission in **System Settings → Privacy & Security → Automation**.
  The mirror shows the visible screen as plain text, refreshed every second, so
  colors and full-screen redraws are not reproduced; commands are sent as
  complete lines.
- The hub relies on the local OpenCode service; when the service is stopped it
  keeps serving cached data and shows an offline state, reconnecting when
  OpenCode returns.
- If the Mac sleeps, the hub cannot answer until it wakes. Turn on **Settings →
  Power → Keep Mac awake** (or set `OPENCODEBAR_PREVENT_SLEEP=1`) to hold an
  idle-sleep assertion while the hub runs.
- Go plan limits come from an undocumented console endpoint. Credits, the
  auto-recharge setting, and extra usage are console-only and are not shown.
- The hub binds `0.0.0.0` by default so the phone can reach it; a Bearer token
  is always required. Use a trusted network, or set `OPENCODEBAR_HUB_HOST=127.0.0.1`
  and a tunnel if you need remote access.
- The iOS app allows arbitrary HTTP loads because the hub is usually a plain
  HTTP address on the LAN; there is no App Store signing setup in the repo yet.
- Mac usage numbers are cached at `~/Library/Caches/OpenCodeBar/usage.json` (safe
  to delete), the iOS app caches sessions, projects, messages, stats, and usage
  in its Application Support container (safe to delete or reinstall), and the hub
  caches everything in `~/.local/share/opencodebar/hub.sqlite` (also safe to
  delete). A stale cache is always preferred over an empty tab.

See [NOTES.md](NOTES.md) for follow-ups and known polish items.

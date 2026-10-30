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
remembered across launches. The iOS app has the same areas — Tasks,
Projects, Usage, Host, VMs, and Settings — adapted for touch, with the same dark panel
design and a floating tab dock. **Host** switches between the System inventory
and Remote desktop, so the phone can also watch and control the Mac's screen.
Its Appearance setting can follow the system or stay dark/light. Both apps can
also start a new session, send a prompt into an open conversation, open
terminals on the Mac to type into them, and build, run, and monitor declarative
NixOS virtual machines on the hub host. On iOS, **Live** and **Usage** Home
Screen widgets bring the same status to the Home Screen in small, medium, and
large sizes.

macOS panel:

![Session detail](docs/screenshots/session.png)
![Session stats](docs/screenshots/stats.png)
![Session changes](docs/screenshots/changes.png)
![Prompts view](docs/screenshots/prompts.png)
![Projects tab](docs/screenshots/projects.png)
![Project detail](docs/screenshots/project-detail.png)
![Usage tab](docs/screenshots/usage.png)

iOS app:

![iOS session activity](docs/screenshots/ios-live.png)
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
- The Tasks tab follows the window width: a wide window shows a board with one
  column per status, filling the available area, while the compact panel and a
  narrow split column keep the filtered single-column list.
- The window remembers its size and position. Right-click (or control-click)
  the menu bar icon for the compact tray panel.
- The window can also be toggled from **Settings → App → Desktop window** and
  is remembered across launches. Closing the window returns to menu-bar-only
  mode; left-clicking the icon opens it again.

**Tasks**
- The first tab is a project-management board built from sessions. Every new
  top-level session becomes a task; running work shows as **In progress**, and
  finishing, stopping, or failing it moves the task to **Needs review**.
- **Queued** tasks start later or wait for capacity. Pick a start time in the
  New Session sheet (like a timed pause), or set **Settings → Agents →
  Concurrent agents** on the hub. Prompts beyond that limit stay queued and
  start in order as running sessions finish. **Start now** overrides the limit
  and **Remove from queue** drops the stored prompt.
- Mark a task **done**, reopen it, dismiss it, or open the conversation and send
  another prompt — which reopens the task automatically. Done tasks are hidden
  by default; the eye button shows or hides them.
- Tasks are labelled from the request with no model call: type (**Bug**,
  **Feature**, **Refactor**, **Tests**, **Docs**, **Performance**, **Security**,
  **Chore**, or **Question**), scope (**Product**, **Technical**, or
  **Infrastructure**), and a risk hint such as **Security-sensitive**,
  **Data loss**, or **Breaking change**. Filters switch between queued, review,
  in progress, done, and every task, and **New task** starts a session directly
  from the board. Project, date (all time, today, last 7 days, or last 30 days),
  and outcome (finished, failed, or interrupted) filters narrow the board too.
- **Group** splits each status column by project, by date (day, week, or month),
  or by date and then project. In the compact panel and a narrow split column it
  groups the single-column list the same way. The mode and interval are
  remembered, and cards inside a project section stop repeating the project
  name.
- Project sections show the project's own app icon when the hub finds artwork
  for it, and keep the folder symbol otherwise. Turn this off in
  **Settings → App → Project icons in Tasks** on macOS or
  **Settings → Appearance** on iOS.
- The board is stored on the hub and synced to both apps, so resolving a task on
  the Mac updates the phone.
- A session that is **Paused** or **Stopped** keeps its badge and continue time
  on its task card. Continue sends `continue` into the conversation, which
  starts a fresh turn. Typing a prompt also releases the hold.

**Sessions**
- Click any session to open its details: the full conversation with the newest
  message first, a prompts-only list with copy buttons, and expandable reasoning
  and tool calls. The view keeps updating while the session runs and pages back
  through history.
- **Reply from the conversation.** The composer at the bottom of the Chat tab
  sends a prompt into that session. A running session queues the message until
  the current turn finishes, and the conversation refreshes as it arrives.
  Queued prompts stay visible above the composer, with an **×** to withdraw one
  before the turn claims it.
- **Recover from a failed turn.** Provider failures are shown in the
  conversation with the upstream message and HTTP status. **Retry here** resends
  the same prompt in the current conversation so the turn can continue.
  **Retry options…** opens a sheet where you can send `continue` instead, pick a
  model, variant, and agent, or fork the conversation before the failed prompt
  into a new session. A fork leaves the original untouched. The session header
  labels a fork with a link back to its source conversation and lists the forks
  of the conversation you are viewing. The header and **Session settings**
  disclosure also show the agent, model, provider, variant, directory, and
  outcome that were actually used.
- **Pause or stop work.** The session header and a project's running and recent
  rows offer **Pause…** and **Stop**. Pausing interrupts the current turn and
  holds the session for a duration or until a clock time you pick; the hub
  continues it automatically at the deadline, even after a restart. Stopping
  holds it until you press **Continue**. A held session leaves the project's
  running list and shows a **Paused** or **Stopped** badge with its continue
  time in the recent list. Continue sends `continue` into the conversation,
  which starts a fresh turn. Typing a prompt also releases the hold.
- **Speak your prompt.** The microphone in the conversation composer and the
  new-session sheet turns speech into text as you talk, using NVIDIA's Parakeet
  model on the Apple Neural Engine. It keeps whatever you already typed, and the
  transcript stays editable before you send. The model downloads once (~450 MB)
  and then dictation works offline; if it cannot be prepared the app falls back
  to the system speech recognizer.
- **Start a new session** from the Tasks tab or a project page: open the
  searchable project browser to sort by recent, name, or running work and
  filter to running, Git, or sandboxed projects, choose **Current folder** or
  **Git worktree** for the workspace, or clone a GitHub/git repository into a
  new folder on the Mac, then choose an optional title and first message. A
  worktree runs the project's setup script before the session starts, keeping
  its changes out of the main checkout. The new session opens immediately, and
  the first message is sent in the same step.
- **Stats** tab: prompts, steps, tool-call reliability, per-tool failure counts
  and median durations, the recent failures with their errors, file impact, and
  the token mix for that session.
- **Changes** tab: every file the session wrote, with the actual patch, added
  and removed line counts, and a colour-coded diff. Repeated edits to one file
  are grouped, and long patches collapse to a preview. The layout button swaps
  the diff cards for a collapsible file tree; tap a file to see its patch. Tool
  cards in the conversation show the same diff instead of raw edit JSON.
- **Git** tab: the branch, HEAD commit, working-tree state, and every commit
  made while the session was active. It uses the same repository data as the
  project page, and sessions outside a work tree say so instead of showing an
  empty list.
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
  grouped by session and file, revealed in pages of 20 files. **Files** lists
  every file in the project folder,
  including untracked files, and marks git working-tree changes as added,
  modified, or deleted; filter it to changed files or search by path. The layout
  button swaps the flat list for a collapsible folder tree.
- **Git** shows the repository's current branch, HEAD, working-tree state, local
  branches, tags, and the full commit graph across every ref. Commits keep their
  parent links, so merges and side branches are drawn as a lane graph instead
  of a flat list. Non-repository folders show an empty state.
- **Flows** brings the project's GitHub Actions pipeline into the same page:
  recent runs, the selected run's workflow, branch, commit and duration, a stage
  strip, jobs grouped into their `needs` dependency stages, the selected job's
  steps and annotations, and the head commit's check runs. Each job and run
  links back to GitHub. Use `GITHUB_TOKEN` / `GH_TOKEN`, or sign in with
  `gh auth login`, so private repositories and the API rate limit work; public
  repositories fall back to anonymous reads. Projects without a GitHub remote
  show an empty state instead.
- **Sessions** lists every session in the project with its cost and time,
  revealed in pages of 50. Quick actions open the project in Finder or Terminal
  and copy its path.
- Duplicate records for the same directory are merged, and analytics are
  fetched per project from the stats API rather than derived from the session
  list.

**Usage**
- OpenCode Go plan limits are pinned above the tab's pages: rolling (5h),
  weekly, and monthly consumption as compact percentage gauges, read from the Go
  usage API. Tapping the header expands the reset countdowns and any stale-data
  note. Hidden when no Go key is configured.
- Usage numbers and plan limits are cached on disk, so the tab keeps showing the
  last known values — flagged as stale — when the service or the API is
  unreachable.
- A segmented picker splits the dashboard into four pages so the panel is not
  one long scroll:
  - **Overview** — streak, active days, today's steps, prompts, sessions, total
    cost, tokens, tool calls, and subagents, followed by the daily trend chart
    for steps, cost, or tokens across the last 30 / 90 / 365 days or all time.
    The token and tool-call tiles jump to their pages.
  - **Activity** — a GitHub-style heatmap of daily agent steps and top projects
    by cost, with the same selectable windows.
  - **Breakdown** — token mix (input / output / reasoning / cache read / cache
    write) and the per-model breakdown with steps and cost.
  - **Tools** — the tool call success/failure summary, tool-type filters, and
    a switchable per-tool view: list, rows, columns, pie, or line.
- The Go plan strip and section picker stay in place while a page scrolls, and
  switching tabs keeps the Usage page you last viewed.

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
- Top processes by CPU or memory, with PID, user, and resident size. The
  **Memory** overview tile opens a searchable Activity Monitor-style view with
  the page breakdown, swap, and the largest processes by memory.
- Installed applications discovered from the OS (with real app icons where
  available, plus versions, bundle ids, sources, and paths) and a searchable
  filter. Open any app for its bundle facts, extensions, signing identity, URL
  schemes and document types. Xcode adds its installed SDKs, shipped
  frameworks, and every simulator runtime and device, with boot, shutdown,
  erase, delete, and runtime-removal controls.
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

**Virtual machines**
- A top-level **VMs** tab on both apps. The hub builds declarative NixOS
  guests, boots them with Apple's Virtualization.framework, and keeps the
  definition, raw EFI disk, SSH key, serial log, and metrics on the host.
- **Create with the configuration builder**: a full click-together NixOS
  builder on both apps. Pick a preset, search and select from categorized
  options (system, desktop, development, containers, services, networking,
  media, AI, monitoring, security, gaming, and advanced), add users with
  groups and SSH keys, choose time zone/locale/keymap, open firewall ports, and
  drop in raw nixpkgs attributes or a custom module body. Dependencies are
  expanded automatically, conflicting choices replace each other, and a live
  build plan previews the real `configuration.nix` from the hub before anything
  is built. The first build runs
  `nix build .#packages.aarch64-linux.default` against a generated flake and
  copies the `raw-efi` image out of the Nix store. Progress and the full build
  log are streamed to the VM page.
- **Lifecycle**: start, stop (graceful, with a forced fallback), restart, pause,
  resume, and delete. Rebuilding replaces the disk after a confirmation.
  Guests keep running when the hub restarts; the next request re-adopts them
  from the helper's runtime record.
- **Monitoring**: helper CPU and RSS, logical and allocated image size, guest
  CPU and load, memory and disk usage, uptime, hostname, kernel, and the current
  NixOS generation. The list shows build and boot progress, the discovered DHCP
  address, pending package changes, and errors.
- **Serial console**: a live, typeable virtio console (`hvc0`) over the hub's
  authenticated WebSocket. Opening it replays the tail of the boot log, so a
  guest that has not reached SSH is still visible and recoverable.
- **Change the configuration declaratively**: reopen **Configure** and edit any
  option, user, service, port, or setting. While the guest is running, the hub
  copies the generated `configuration.nix` and runs `nixos-rebuild switch` over
  SSH; while it is stopped, the change is queued for the next boot. The older
  **Packages** tab remains for raw nixpkgs attributes. Base tools are curl, git,
  htop, and vim.
- **Per-VM SSH**: each guest gets a generated ed25519 key, a passwordless-sudo
  `opencodebar` user, SSH key authentication only, and a host-only NAT address
  discovered from the ARP table. The detail page copies the SSH command.
- Setup is explicit rather than silent: the VMs tab reports whether the helper
  is signed with the Virtualization entitlement, whether Nix is installed, and
  whether Nix has an `aarch64-linux` builder, with the exact commands to fix
  each case. **Run** installs Nix or rebuilds/signs the helper from the app; the
  Nix installer runs in Terminal on the Mac and streams the installer log back
  to the VMs tab. The Linux builder command stays copyable for Terminal because
  the builder VM must keep running. Once configured, it appears as a read-only
  **Host build service** card, separate from the guest list, because it is a Nix
  build service rather than an app-managed guest. **Setup logs** keeps the Nix,
  helper, and builder console logs under
  `~/.local/share/opencodebar/vms/setup/` and exposes them in the app; each new
  run rotates the previous file. A log may show the literal `Password:` prompt,
  but never the password itself.

**Settings**
- Every app connected to the hub — macOS, iOS, and iPadOS — with its device
  name, platform, app version, and whether it is live right now. Click a device
  for its stable ID, first and last seen timestamps, and live connection state.
- **Deployments**: every paired iPhone/iPad with the OpenCodeBar builds
  installed on it right now — the normal app and each side-by-side variant —
  plus install history with version/build, commit, branch, and worktree. Click
  a device for its full history. **Scan** asks the hub to run `xcrun devicectl`
  and reconcile the device, so builds installed from Xcode or another checkout
  appear too; `make mobile-device` and `make mobile-variants` report each
  install automatically.
- Server information: hub version, address, uptime, cached session/message
  counts, OpenCode state, last sync, and the SQLite path.
- Server controls: sync now, restart the hub, reveal its data/config files, and
  refresh. Pairing shows a scannable QR code plus the copyable link for adding
  another phone.
- **Power**: choose whether the Mac may sleep while the hub runs. Keeping it
  awake holds an idle-sleep assertion so phones and tablets keep their
  connection; the display can still turn off. The preference is stored by the
  hub and applied again after a restart.
- **Agents**: cap how many sessions may run at once (`0` means unlimited).
  Prompts beyond the cap wait in the task board's **Queued** column and start in
  order as slots free up. The limit is stored by the hub and shared by every
  connected app.
- **Developer**: a live, in-memory activity log of hub requests, sync cycles,
  event-stream changes, and errors. Filter by type, pause the view while
  reading, copy the visible entries, or clear it. Entries never include the hub
  token or request bodies.

**iPhone & iPad**
- The same Tasks, Projects, Usage, Host, VMs, and Settings areas as the Mac
  panel, with the same compact panel design, live-activity folding, and a
  floating tab dock built for touch. **Host** has a System/Remote switch:
  System opens on a compact dashboard with live vitals, Now Playing, and a
  **More** grid. The vitals double as navigation — CPU opens Performance,
  storage opens Storage, battery or health opens Health, and system/uptime open
  Machine — while the grid adds Network, Software, Terminals, and Files. The
  phone can monitor CPU, memory, disks, processes, Homebrew, and installed apps
  without scrolling through one long inventory — and browse the Mac's files
  with the same read-only browser. The latest host snapshot and any app or
  project icons the phone has seen are cached in local SQLite, so the Host tab
  still renders with cached data while the hub is offline. Remote streams and
  controls the Mac's display with touch and keyboard input.
  **VMs** creates and drives NixOS guests, with the serial console and package
  editor adapted for touch.
- Search projects, pull to refresh any screen, and open a session from a deep
  link. Settings shows hub and OpenCode health, cached session/message counts,
  uptime, last sync, and a **Keep Mac awake** switch for the host Mac. A
  **Developer** page shows the same in-memory activity log of API requests,
  syncs, events, and errors as the Mac app.
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

Both apps can start sessions and send prompts, pause or stop a session, and
continue held work. Neither deletes sessions. Both can also list and drive
terminals on the hub host, and create, run, monitor, update, and delete NixOS
virtual machines.

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
   stops or restarts on a new port. Writes from the apps — creating a session,
   prompting one, and pausing, stopping, or continuing work — are forwarded to
   the same service.
3. Serves a stable API that mirrors OpenCode's shapes — `/api/session`,
   `/api/session/{id}`, `/api/session/{id}/message`, `/api/session/{id}/changes`,
   `/api/session/{id}/stats`, `/api/session/{id}/git`,
   `/api/session/{id}/forks`, `/api/project`,
   `/api/project/{id}/changes`, `/api/project/{id}/files`,
   `/api/project/{id}/git`, `/api/project/{id}/flows`,
   `/api/project/{id}/icon`,
   `/api/experimental/session/stats` — plus
   `/api/session/{id}/prompt` (`POST`), `/api/session/{id}/pause` (`POST`),
   `/api/session/{id}/stop` (`POST`), `/api/session/{id}/continue` (`POST`),
   `/api/session` (`POST`),
   `/api/task` (`GET`), `/api/task/{id}` (`PATCH`), `/api/usage`,
   `/api/git/clone` (`POST`), `/api/worktree` (`POST`), `/api/health`,
   `/api/system`, `/api/system/apps/icon`,
   `/api/system/apps/detail`, `/api/system/apps/action` (`POST`),
   `/api/terminals` (`GET`/`POST`),
   `/api/terminals/{id}` (`GET`/`PUT`/`DELETE`),
   `/api/terminals/{id}/socket` (WebSocket), `/api/host-terminals`,
   `/api/host-terminals/{id}`, `/api/host-terminals/{id}/command`,
   `/api/host-terminals/{id}/focus`, `/api/files`, `/api/files/content`,
   `/api/files/raw`, `/api/vms`, `/api/vms/capabilities`,
   `/api/vms/catalog`, `/api/vms/preview` (`POST`),
   `/api/vms/{id}` (`GET`/`PATCH`/`DELETE`),
   `/api/vms/{id}/preview` (`POST`),
   `/api/vms/{id}/{start|stop|restart|pause|resume|rebuild|apply}` (`POST`),
   `/api/vms/{id}/log`, `/api/vms/{id}/console/socket` (WebSocket),
   `/api/vms/setup` (`GET`/`POST`), `/api/vms/setup/cancel` (`POST`),
   `/api/vms/setup/logs`, `/api/vms/setup/log`,
   `/api/devices`, `/api/deployments` (`GET`/`POST`),
   `/api/deployments/scan` (`POST`), `/api/settings` (`GET`/`PATCH`),
   `/api/sync` (`GET` delta feed, `POST` force sync),
   `/api/server/restart` (`POST`), and `/api/event`. Clients authenticate with a
   Bearer token and identify their platform with `X-OpenCodeBar-*` headers so
   the settings screen can list connected devices.
4. Forwards OpenCode events to every connected client, so both apps update live.
   Rapid updates are coalesced into a configurable window (`eventThrottleMs`,
   250 ms by default) before delivery. The stream also carries `hub.*` notices
   (`hub.connected`, `hub.sessions`, `hub.stats`, `hub.usage`) that tell clients
   when cached data changed.

Interactive API documentation is served by the hub at `/api/docs` (Swagger UI),
with the raw OpenAPI 3.0 document at `/api/openapi.json`. Both routes are public;
click **Authorize** and paste the hub token to run authenticated **Try it out**
requests. The same reference is published at
<https://403access.github.io/ai-tools/docs/api/> and documented in
[`website/docs/hub/api.md`](website/docs/hub/api.md).

Endpoints the hub reads from OpenCode: `/api/info`, `/api/session`,
`/api/session/active`, `/api/session/{id}`, `/api/session/{id}/message`,
`/api/project`, `/api/experimental/session/stats`, `/api/pty`, and
`/api/event`. It writes through `POST /api/session`,
`POST /api/session/{id}/prompt`, `POST /api/session/{id}/interrupt`, and the PTY
create/update/delete routes. Each terminal WebSocket is proxied to
`/api/pty/{id}/connect`; the hub opens that upstream socket with OpenCode's
Basic credentials so clients only need the hub token.

The VM backend is a small Swift helper, `OpenCodeBarVZ`, signed with
`com.apple.security.virtualization`. The hub spawns one detached helper per
running guest and talks to it over loopback TCP: a JSON-lines control port and a
raw serial port. The helper writes `runtime.json` with its pid and both ports,
so a restarted hub can re-adopt a guest. It configures a raw EFI disk,
Virtualization.framework NAT networking, and a virtio console; the hub finds the
guest's DHCP address from `arp -an` or the serial log, then uses SSH for metrics
and `nixos-rebuild`. The generated flake exposes both
`nixosConfigurations.<host>` and the `system.build.images.raw-efi` package, so
the host build and the in-guest rebuild share one `configuration.nix`.

The event stream does more than trigger refreshes. `session.step.*`,
`session.reasoning.*`, `session.text.*`, `session.tool.*`, `session.usage.*`,
and `permission.*` events are folded into a per-session activity snapshot, which
is what session headers and Home Screen widgets show. Cost and token counts move
as `session.usage.updated` arrives instead of waiting for the next poll. When the stream is missed — on
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

## Privacy and model providers

OpenCodeBar has no hosted service, telemetry, or analytics. The hub and apps run
locally, and the hub cache stays in
`~/.local/share/opencodebar/hub.sqlite`. Prompts still go through OpenCode to
the model provider configured there, so that provider's logging, retention, and
training terms apply.

**Never enable an endpoint's training opt-in just to use OpenCodeBar.** Some
OpenCode Go models require the workspace option **Allow paid endpoints that
train on request data**. OpenCode CLI does not need it, and neither do the apps.
OpenCodeBar never changes OpenCode or workspace privacy settings, and it does
not require that option. If a turn fails with the training error, choose a model
whose policy you accept (the **Retry options…** action on a failed turn lets
you pick one), or set a non-training model as OpenCode's default.

New sessions inherit OpenCode's default model for the directory; they do not
copy the model from your most recent CLI session. The session header and
**Session settings** disclosure show the model, provider, variant, and agent
that actually ran, so you can verify what a phone-created session used.

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
- **Virtual machines** need an Apple silicon Mac running macOS 14 or later.
  Building the NixOS image also needs [Nix](https://nixos.org/download) with an
  `aarch64-linux` builder. On macOS the easiest builder is
  `nix --extra-experimental-features 'nix-command flakes' run nixpkgs#darwin.linux-builder` (or nix-darwin's
  `nix.linux-builder.enable`), which starts a cached NixOS builder VM and asks
  for the Nix daemon settings once. The VMs tab checks both prerequisites and
  can run the Nix installer or rebuild the helper with **Run**; the Nix step
  opens Terminal.app on the Mac and streams the log back to the app. The Linux
  builder is copyable for Terminal because it must stay running; after it
  starts, add the builders/SSH config from the Virtual machines guide (or use
  nix-darwin's `nix.linux-builder.enable`). Once configured, the VMs tab lists it
  as a read-only **Host build service** card, separate from guests and with a
  link to its log. `make hub` builds and ad-hoc signs the helper with
  `com.apple.security.virtualization`; `make vz-helper` rebuilds it alone.

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

Device installs are recorded in the hub automatically; Settings → Deployments
shows what is installed now and the install history. Pass `--no-report` to
`Scripts/run-mobile-device.sh` to skip the record.

To install without a cable or a shared network, publish an over-the-air build:

```sh
make hub-tunnel    # terminal 2: public HTTPS URL, needed off the LAN
make mobile-ota    # archive, export, publish; prints a link and QR code
```

The phone opens the link or scans the QR, taps **Install**, and iOS confirms.
When the phone is on USB or the same Wi-Fi, `make mobile-ota ARGS="--install"`
installs it directly with `devicectl` and still publishes the link as a
fallback.

The same build is available from the Mac app's **Settings → Deployments →
Build & install** button, which tries the direct install too; connected phone
apps show an **Update available** banner when a new build is published. iOS
cannot be made to install from the hub alone: without an MDM server the
confirmation always happens on the phone.

```sh
make run        # build dist/OpenCodeBar.app and launch it
make restart    # rebuild and restart the running app
make watch      # rebuild/relaunch automatically when Sources change
```

`make restart` runs `Scripts/restart.sh`, which builds first and only then
stops the old instance — so a failed build leaves the current app running.
The script can also be called directly:

```sh
Scripts/restart.sh --no-build      # relaunch the existing bundle
CONFIG=debug Scripts/restart.sh    # rebuild a debug bundle instead
```

`make watch` runs `Scripts/watch.sh` for a live-reload loop. It builds a debug
bundle, launches it, then rebuilds and relaunches whenever a Swift file under
`Sources/OpenCodeBar`, `Package.swift`, or `Package.resolved` changes. Saves are
debounced, and a failed build leaves the running app untouched. This restarts
the process, so in-memory UI state (open panel, selected session) is reset; it
is not in-place hot patching.

```sh
Scripts/watch.sh --no-initial      # watch without the initial build
CONFIG=release Scripts/watch.sh    # watch with release builds
INTERVAL=1 Scripts/watch.sh        # poll once a second instead of 0.5s
```

### Find the app in Spotlight and Raycast

`make app` leaves the bundle in `dist/`, which is build output: Raycast only
indexes application folders such as `/Applications` and `~/Applications`, and
every build deletes and recreates the bundle in `dist/`, so cached Launch
Services and Spotlight records go stale. Install it into `~/Applications` to
give both tools a stable path:

```sh
make install       # build, copy to ~/Applications, register, relaunch
make uninstall     # stop, remove, unregister
```

`Scripts/install.sh` copies `dist/OpenCodeBar.app` to
`~/Applications/OpenCodeBar.app`, re-signs it ad hoc, re-registers it with
Launch Services, and nudges the Spotlight index. `dist/` stays the build output;
the installed copy is what Spotlight and Raycast launch.

This is an explicit step, not part of every build. After a change you want to
use, run `make install` again: it stops the running instance (from either path),
swaps the bundle atomically, and relaunches the installed copy. The script
prints any other registered copies of the same bundle id, which happens when
several worktrees have built the app.

```sh
Scripts/install.sh --no-build      # reinstall the existing dist/ bundle
Scripts/install.sh --no-restart    # install without relaunching
CONFIG=debug Scripts/install.sh    # install a debug bundle
INSTALL_DIR=/Applications Scripts/install.sh
```

The app is a menu bar agent (`LSUIElement`), so it never appears in Launchpad or
Cmd-Tab and has no Dock icon; Spotlight and Raycast still list it as an
application. If Raycast does not show it yet, run **Refresh Applications** in
Raycast's **Search Applications** extension (or toggle the extension off and on)
to rebuild its index.

Other targets:

```sh
make build         # swift build (debug)
make test          # swift test
make bench         # shared-code performance microbenchmarks
make app           # assemble dist/OpenCodeBar.app (release)
make install       # build and install into ~/Applications (Spotlight, Raycast)
make uninstall     # remove the installed copy
make preview       # open the panel in a normal window for design work
make shots         # regenerate docs/screenshots
make icon          # regenerate the app icon
make hub           # run the SQLite sync hub (foreground)
make hub-dev       # hub with auto-reload
make hub-test      # hub unit tests (Bun)
make hub-tunnel    # expose the hub through a Cloudflare quick tunnel
make remote-host   # build the ScreenCaptureKit remote-desktop helper
make vz-helper     # build and sign the Virtualization.framework VM helper
make mobile-build  # build the iOS app and widget extension for the simulator
make mobile-run    # build, install, launch, and pair the iOS app in a simulator
make mobile-device # the same on a connected iPhone/iPad
make mobile-variants # one installable app per git worktree
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

### Review several versions side by side

`make mobile-variants` installs one app per git worktree on the same phone, so
branches can be compared without replacing each other or the normal app:

```sh
make hub                  # terminal 1
make mobile-variants      # terminal 2: every worktree

Scripts/run-mobile-variants.sh --list             # show names and bundle ids
Scripts/run-mobile-variants.sh main feature/kanban  # pick worktrees or branches
Scripts/run-mobile-variants.sh "VMs=../vms"        # choose the display name
make mobile-variants ARGS="--no-build"             # reinstall the last builds
```

Each variant is installed as `dev.opencodebar.mobile.<slug>` with an
`OCB <label>` home-screen name (the widget extension follows the same prefix)
and its own DerivedData folder under `.build/`. The suffix comes from `VARIANT_SUFFIX` in
`project.yml`, which the wrapper passes to `xcodebuild`; worktrees that predate
the placeholders are patched temporarily and restored afterwards. Variants have
separate containers and caches but share the keychain access group, so pairing
one pairs all of them and the hub lists the phone once. Every variant also
registers the `opencodebar://` scheme, so widget taps may open another copy.

See [Review builds side by side](website/docs/development/variant-builds.md) for
naming, signing and App ID limits, clean-up, and troubleshooting.

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

To launch the Mac app at login, add `~/Applications/OpenCodeBar.app` (the copy
`make install` creates) in **System Settings → General → Login Items**, not the
bundle in `dist/`, which is recreated by every build. The hub can run as a launch
agent if you want the phone to reach it without starting a terminal.

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

### Design mirror (OpenPencil)

[`design/OpenCodeBar.fig`](design/OpenCodeBar.fig) is a complete visual mirror of the product in
[OpenPencil](https://openpencil.dev): the macOS menu bar, panel and desktop
window, iPhone and iPad, Home Screen widgets, the hub architecture, every
important empty/loading/error/stale/permission state, and the roadmap for the
mirror itself. It uses synthetic demo data, so it can be opened and shared
without a hub.

```sh
open -a OpenPencil design/OpenCodeBar.fig
node design/build.mjs            # regenerate page JSX
OPENPENCIL_DOC=tab-1 node design/build.mjs --render   # render into the app
```

See [`design/README.md`](design/README.md) for the page index, conventions and
rebuild steps, and [`design/TODO.md`](design/TODO.md) for coverage.

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
    DevLog.swift            in-memory activity log for the Developer view (shared)
    HubModels.swift         hub transport/health models
    HubEventStream.swift    SSE subscription with reconnect (shared)
    RemoteDesktopModels.swift  remote status, frame header, modifiers (shared)
    HubDiscovery.swift      reads the hub URL + token (macOS)
    ServiceDiscovery.swift  OpenCode config paths
    DeviceIdentity.swift    stable client id + platform headers (shared)
    WidgetShared.swift      shared keychain + widget snapshot cache
    UsageCache.swift        last-known usage on disk
    TerminalConnection.swift  terminal WebSocket, input and resize bridging (shared)
    VMConsoleConnection.swift serial-console WebSocket client (shared)
    VirtualMachinesStore.swift shared VM list, polling, actions, and logs
    NixOSBuilderModel.swift  dependency resolution, presets, users, and preview (shared)
    HostTerminalMirror.swift  Terminal.app text mirror and command input (shared)
  Support/
    QRCode.swift            pairing QR rendering
  Models/                   Codable models, split by domain (shared)
    TokenUsage.swift        token/model primitives
    Session.swift           sessions and projects
    Stats.swift             aggregate and per-session statistics
    Messages.swift          messages, parts and pending prompts
    Catalog.swift           OpenCode model/agent catalogs and failed-turn lookup
    Changes.swift           file patches and grouping
    ProjectFiles.swift      project file browser payloads
    GitInfo.swift           commit, branch, and repository graph models (shared)
    GitHubFlows.swift       workflow runs, stages, jobs and checks (shared)
    APIEnvelopes.swift      request/response envelopes
    OpenCodeEvent.swift     decoded event payloads (shared)
    ProjectOrdering.swift   project merge + ordering from running counts (shared)
    ProjectFiltering.swift  project search, sort, filter, and grouping (shared)
    SessionActivity.swift   live "what is it doing" state (shared)
    SessionActivity+Events.swift  event folding
    SessionActivity+Derive.swift  rebuild from cached messages
    SubagentOrdering.swift  running-first ordering for child sessions
    SessionOrdering.swift   most-recent-first ordering for feeds
    WidgetSnapshot.swift    compact widget payload shared by app and extension
    SessionFilter.swift     project/date/outcome filters and date grouping
    GoUsage.swift           Go plan windows (shared)
    SystemInfo.swift        machine inventory from the system endpoint (shared)
    Terminals.swift         OpenCode PTY sessions and requests (shared)
    HostTerminals.swift     Terminal.app tab models (shared)
    HostFiles.swift         host directory listings and previews (shared)
    VirtualMachine.swift    VM definitions, metrics, capabilities (shared)
  Views/                    SwiftUI panel, tabs, heatmap, components
    DesktopView.swift       full-window layout with a persistent sidebar
    TasksTab.swift          task board, filters, and grouping
    ChangeViews.swift       patch cards and change summaries
    NewSessionSheet.swift   start a session with an optional first prompt
    ProjectPickerSheet.swift  searchable, sortable, filterable project browser
    RetryTurnSheet.swift    retry in place or fork, with model/agent choices
    ModelPickerSheet.swift  searchable, filterable model browser
    PerformanceViews.swift  skeleton placeholders and shimmer (shared)
    SessionDetailView.swift session header and tabs
    SessionDetailView+Composer.swift  pending queue and composer
    SessionDetailView+Content.swift   conversation/stats/changes/prompts
    SessionDetailView+Loading.swift   message paging
    SessionMessageViews.swift         message, part and prompt cards
    ProjectDetailView.swift           project header, tabs, and sections
    ProjectDetailAnalytics.swift      scoped at-a-glance stats
    ProjectSessions.swift             recent-session rows
    GitViews.swift                    session commits and project commit graph
    FlowsViews.swift                  GitHub Actions stages, jobs and checks
    SettingsTab.swift       connected devices and server controls
    SystemTab.swift         machine, resources, apps, Homebrew and tools
    SystemAppDetailView.swift  app bundle facts and Xcode simulator management
    TerminalViews.swift     terminal list, new-terminal sheet and terminal window
    TerminalEmulatorView.swift  SwiftTerm host for Mac and iOS
    VirtualMachinesTab.swift      VM list, lifecycle actions, setup card
    VirtualMachineDetailView.swift  VM overview, console, packages, logs
    NewVirtualMachineSheet.swift   create or configure a NixOS guest
    NixOSBuilderView.swift  catalog browser, users, presets, live build plan (shared)
    VMComponents.swift      serial console pane and VM setup notice (shared)
    SystemFileBrowser.swift host folder navigation and text/image preview
    SettingsTab+Support.swift         derived labels and actions
    SettingsDeviceRow.swift           device row in the connected list
    SettingsDeviceDetail.swift        status, timestamps and identity for one device
    SettingsDeveloperSection.swift    live API/sync/event activity log
    SessionStatsView.swift  per-session reliability and failures
    SubagentViews.swift     tap-through child-session tree
  Preview/PreviewRunner.swift

Sources/OpenCodeBarRemoteHost/  ScreenCaptureKit helper for remote desktop
  main.swift                stdio entry point, AppKit run loop
  RemoteHost.swift          capture, permissions, pointer/key board input
  Wire.swift                framed status/frame/log transport

Sources/OpenCodeBarVZ/        Virtualization.framework helper for NixOS guests
  main.swift                CLI entry, listeners, runtime record, signals
  VMRunner.swift            EFI boot, raw disk, NAT, CPU/memory, lifecycle
  SerialConsole.swift       virtio console <-> loopback socket + log
  ControlServer.swift       JSON-lines control protocol
  Support.swift             config/runtime models, loopback TCP, fd I/O
  OpenCodeBarVZ.entitlements  com.apple.security.virtualization

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
  TasksView.swift             task board, project/date/status filters
  TasksView+Filters.swift     filter menus and date grouping
  SessionDetailView.swift     conversation, stats, changes, git, prompts, subagents
  MobileGitViews.swift        session commits and project commit graph
  SessionDetailView+Header.swift    live summary
  SessionDetailView+Composer.swift  pending queue and composer
  SessionDetailView+Content.swift   tab content
  SessionDetailView+Pieces.swift    shared loading/error views
  SessionDetailView+Loading.swift   message paging
  NewSessionSheet.swift       start a session from the phone
  ProjectPickerView.swift     searchable, sortable, filterable project browser
  RetryTurnSheet.swift        retry in place or fork, with model/agent choices
  ModelPickerView.swift       searchable, filterable model browser
  MobileMessageViews.swift    message cards
  MobileChangeViews.swift     patch cards and change summaries
  MobileSessionStatsView.swift  per-session reliability and failures
  ProjectsView.swift          project list + search
  ProjectDetailView.swift     scoped analytics and project changes
  UsageView.swift             plan limits, trends, stats
  SystemView.swift            host dashboard, live vitals and Now Playing
  SystemCategoryView.swift    focused performance/storage/network/software pages
  SystemComponents.swift      shared system tiles, rows, bars and formatting
  HostView.swift              System/Remote switch for the Host tab
  RemoteDesktopView.swift     remote display, controls, permission cards
  RemoteDesktopSurface.swift  zoomable display view and touch gestures
  RemoteDesktopConnection.swift  frame WebSocket, decoding, pointer/key input
  MobileTerminalViews.swift   terminal list, new-terminal sheet and terminal sheet
  MobileStore+Terminals.swift terminal polling, creation and removal
  MobileStore+HostTerminals.swift Terminal.app tab polling
  VirtualMachinesView.swift   VM list, create sheet, lifecycle actions
  VirtualMachineMobileDetailView.swift  VM overview, console, packages, logs
  NewVirtualMachineSheet.swift  create or configure a NixOS guest from the phone
  MobileFileBrowser.swift     host folders and file previews
  MobileCharts.swift          Swift Charts trend cards
  SettingsView.swift          appearance, pairing, and status
  SettingsView+Connection.swift  status and hub connection controls
  DeveloperView.swift         full-screen activity log for iPhone/iPad
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
  src/vms/                    VM store, NixOS catalog/builder renderer, builds, helper client
  src/api/vm-socket.ts        WebSocket proxy for VM serial consoles
  src/db.ts                   SQLite facade
  src/db/                     schema, row mapping, stores, queries
  src/hub.ts                  polling/event hub facade
  src/hub/                    event bus, sync, reads, usage cache
  src/files.ts                project file browser
  src/git.ts                  session commits and project commit graph
  src/github.ts               GitHub Actions runs, stages, needs and checks
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

design/                       OpenPencil design mirror (generated)
  OpenCodeBar.fig             full product design: 14 pages, all states
  README.md                   how to open and regenerate the file
  ROADMAP.md                  phases, milestones, risks, definition of done
  TODO.md                     live coverage checklist
  build.mjs                   render pages into the open OpenPencil document
  gen/                        one JSX module per page + shared component kit

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
  watch.sh                    rebuild and relaunch on source changes
  run-mobile-device.sh        install on a phone and report the deployment
  run-mobile.sh               install, launch, and pair the iOS app in a simulator
  run-mobile-device.sh        the same on a physical iPhone/iPad
  run-mobile-variants.sh      one side-by-side app variant per git worktree
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
  `--preview --tab usage` opens the Usage tab directly. Add
  `--usage-mode overview|activity|breakdown|tools` to open a specific Usage
  page.
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
- iOS screenshot tooling (Debug builds): `OPENCODEBAR_TAB=live|projects|usage|vms|settings`
  selects the starting tab, `OPENCODEBAR_OPEN_SESSION=running` (or a session id)
  opens a session on launch, and `OPENCODEBAR_OPEN_VM=<id-or-name>` opens a VM.
  Debug builds can also pair from the environment with
  `OPENCODEBAR_HUB_URL` / `OPENCODEBAR_HUB_TOKEN`, which avoids the system URL
  confirmation. With `simctl`:
  `SIMCTL_CHILD_OPENCODEBAR_TAB=usage xcrun simctl launch booted dev.opencodebar.mobile`.
- Hub environment: `OPENCODEBAR_HUB_PORT` (default 8787),
  `OPENCODEBAR_HUB_HOST`, `OPENCODEBAR_HUB_DB`, `OPENCODEBAR_HUB_TOKEN`,
  `OPENCODEBAR_HUB_URL` (clients), `OPENCODEBAR_PREVENT_SLEEP` (`1` holds an
  idle-sleep assertion while the hub runs),
  `OPENCODEBAR_MAX_CONCURRENT_AGENTS` (`0` means unlimited; default `0`),
  `OPENCODEBAR_LOG_LEVEL`.
- VM environment: `OPENCODEBAR_VM_DIR` (default
  `~/.local/share/opencodebar/vms`), `OPENCODEBAR_VZ_HELPER`,
  `OPENCODEBAR_NIX`, and `OPENCODEBAR_NIXOS_CHANNEL` (default `nixos-26.05`).
- Host setup logs are kept in `$OPENCODEBAR_VM_DIR/setup/` as `nix.log`,
  `helper.log`, and `builder.log`, with rotated
  `nix-<timestamp>.log`/`helper-<timestamp>.log`/`builder-<timestamp>.log`
  history. The VMs tab's **Setup logs** button shows them, and the hub serves
  them at `GET /api/vms/setup/log?step=nix|helper|builder`.
- The VZ helper must be signed with `com.apple.security.virtualization`; a bare
  `swift build` does not add it. Use `make vz-helper` (or `make hub`, which
  builds and signs it) after changing the helper. Without the entitlement
  Virtualization.framework rejects the configuration.
- `OPENCODE_GO_USAGE_URL` points the hub's Go limits client at a different URL,
  which is how the Plan limits UI is exercised without a live Go key.
- `OPENCODE_API_KEY` overrides the Go API key read from `auth.json`, and
  `OPENCODE_GO_USAGE_KEY` overrides both. GUI-launched builds may not inherit
  a shell environment, so `~/.config/opencode/opencodebar.json` is usually the
  more reliable place to keep a usage-only key.

## Limitations

- The Mac app needs macOS 14+; the mobile app needs iOS 17+. The hub is a Bun
  process that must be reachable over the network for the phone.
- The apps can start sessions, send prompts, pause or stop work, and continue a
  held session, but they cannot delete sessions. Pausing or stopping interrupts
  the current turn; **Continue** sends a new `continue` prompt rather than
  resuming the exact interrupted turn. An interrupted turn keeps its history and
  outcome. Prompts sent to a running session are queued behind the current turn.
- Terminal access runs commands as the same user as the hub and OpenCode. The
  hub token protects it, but anyone with the token can run anything that user
  can. Keep the token private and use a trusted network or a tunnel.
- Terminal.app tabs are read and controlled through macOS Automation. The hub
  needs permission in **System Settings → Privacy & Security → Automation**.
  The mirror shows the visible screen as plain text, refreshed every second, so
  colors and full-screen redraws are not reproduced; commands are sent as
  complete lines.
- Virtual machines require an Apple silicon Mac and macOS 14+. They do not run
  on an Intel Mac or on a Linux/Windows hub host.
- Building a NixOS image needs Nix plus an `aarch64-linux` builder. The first
  build downloads and assembles a full system, so it can take a long time; the
  hub streams the log and reports failures instead of blocking the app.
- Rebuilding replaces the guest disk; there are no snapshots, clones, suspend
  images, or disk resizing. There is also no graphical console, GPU
  acceleration, USB passthrough, or VNC: the serial console and SSH are the
  management surfaces.
- Installing packages while the guest is running runs `nixos-rebuild switch`
  inside the guest and therefore needs the guest to reach the Nix binary cache.
  A stopped guest queues the change for the next boot. The NixOS channel is
  fixed when the VM is created.
- The hub token controls the VM lifecycle and serial console, like it controls
  terminals and remote desktop. Helpers listen on loopback only, but anyone with
  the hub token can start, stop, or delete guests.
- The helper is ad-hoc signed for local use. A distributed build should sign it
  with the app's Developer ID and include the helper in the bundle.
- VMs keep running when the hub exits or restarts; the next request re-adopts
  them. Stop them from the VMs tab when you are done, or they keep using host
  CPU and memory until the Mac reboots.
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

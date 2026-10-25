# Notes

Working notes for OpenCodeBar: follow-ups, known polish items, and environment
observations. Last updated 2026-10-25.

## Hub and mobile (v2)

The app is now two clients over one hub:

- `server/` — Bun + TypeScript + SQLite. Discovers OpenCode, polls it, stores
  sessions/projects/messages/stats/usage, mirrors the read API, and forwards the
  event stream. Tests: `make hub-test`.
- `Sources/OpenCodeBarMobile/` — iOS app (XcodeGen target) with the same four
  areas as the Mac panel. Build: `make mobile-run`.

Follow-ups worth considering:

- **Ship the hub as a launch agent.** Right now `make hub` is a foreground
  process. A `launchd` plist (with `KeepAlive`) would let the phone reach the
  hub without a terminal open. Documented as a note in the README.
- **iOS distribution.** The repo builds for the simulator and installs on a
  connected device with `make mobile-device`, which uses the Apple Development
  identity and team already configured in Xcode (override with
  `DEVELOPMENT_TEAM=…` or `DEVICE=…`) and pairs over the LAN or a running
  `make hub-tunnel` URL. There is still no App Store/TestFlight
  distribution setup (distribution certificate, upload workflow), and
  `NSAllowsArbitraryLoads` should become a scoped ATS exception (or an HTTPS
  tunnel) before any store build.
- **Remote access.** The hub binds `0.0.0.0` with a Bearer token.
  `make hub-tunnel` starts a Cloudflare quick tunnel, prints a pairing link, and
  writes `~/.config/opencode/opencodebar-hub-tunnel.json`; `make mobile-device`
  and the Mac app's QR code prefer that URL while it runs. Quick tunnels are
  ephemeral and public, so for regular use prefer Tailscale (or a named
  Cloudflare tunnel) and `OPENCODEBAR_HUB_HOST=127.0.0.1`.
- **USB tethering is one-way for app traffic.** With the iPhone providing
  Personal Hotspot, the Mac gets `192.0.0.2/32` on `en0` and reaches the
  internet, but iOS apps on the phone cannot connect back to `192.0.0.2`
  (Safari reports “not connected to the internet”). Use the tunnel or Wi-Fi.
- **Message cache growth.** Every session opened is cached in
  `messages` forever, and the `changes` table mirrors every patch found there.
  Add a retention policy (e.g. keep the newest N per session, or drop sessions
  untouched for 90 days) once the DB grows.
- **Project changes hydrate a bounded window.** `/api/project/{id}/changes`
  pulls message history for the newest 10 sessions by default (four pages per
  session, six-second timeout each, two sessions at a time), then aggregates
  every cached patch in the project. This keeps the first open from monopolizing
  the local OpenCode service; very old sessions that were never opened are not
  hydrated automatically. Raise `?sessions=` or open the session's Changes tab
  to include them.
- **Server-side activity snapshots.** Clients fold events into `SessionActivity`
  themselves (shared Swift code). A newly connected client has no history until
  it seeds from the newest messages, which is fine for now but means the first
  render can lag a few seconds. Storing snapshots in SQLite and serving
  `/api/activity` would remove that.
- **iOS extras.** Home Screen widgets for active sessions and usage now ship in
  the widget extension. A Live Activity for a running session and background
  refresh would make the phone more useful without opening the app.
- **Terminal list fan-out.** `/api/terminals` merges PTYs from the default
  location and every cached project directory. That is one local OpenCode
  request per location (capped at 80, six at a time) behind a 1.5s cache. A
  dedicated location index or a PTY event subscription on the OpenCode side
  would remove the fan-out for large project sets.
- **Terminal socket ownership.** The hub proxies one WebSocket per client and
  leaves the PTY running when the socket closes. There is no controller/observer
  arbitration for two clients typing at once; the last writer wins. Consider
  surfacing the OpenCode connection role if it becomes noisy.
- **Terminal.app mirror is line-based.** macOS does not expose the PTY master
  for an existing tab, so the hub reads `contents` and runs commands with
  `do script`. Raw keystrokes (arrows, Ctrl-C) would need Accessibility
  permission plus System Events, and would still leave the output as a text
  mirror. iTerm2 and IDE terminals are not covered; add them only if their
  scripting APIs can provide a stable tty + contents pair.
- **Website and docs.** `docs/index.html` covers both apps, screenshots, the
  shared hub, and the install flow. The Docusaurus site in `website/` holds the
  full guides, API reference, configuration, and troubleshooting, published at
  `/docs/` by `.github/workflows/deploy-pages.yml`. Keep both in sync when
  screens, commands, or endpoints change.

## Remote desktop (2026-10-25)

The iOS app's **Host → Remote** segment can now stream and control the Mac.
The hub spawns `OpenCodeBarRemoteHost` (a small Swift/ScreenCaptureKit helper)
on demand and relays its frames and input over one authenticated WebSocket.

- **Transport.** Helper → hub is a framed stdio protocol (`Wire.swift`):
  `[kind][u32 length][payload]`; frames carry `RD`, sequence, timestamp, size,
  then a JPEG. The hub re-frames the same bytes for clients as binary WebSocket
  messages and broadcasts JSON status/log events alongside them. `GET
  /api/remote` reports helper availability, displays, permissions, and capture
  settings; `GET /api/remote/socket` is the stream; `POST /api/remote/configure`
  and `/api/remote/permissions` are the control endpoints.
- **Capture.** ScreenCaptureKit captures the selected `SCDisplay` at up to
  1600 px wide, 12 fps, JPEG quality 0.6 by default. The iOS quality menu offers
  Sharp (1920/18fps/0.72), Balanced, and Fast (1280/8fps/0.45). Encoding drops
  frames while a previous frame is still being encoded and the hub drops frames
  for a client with more than 4 MB queued.
- **Input.** Normalized 0–1 coordinates map to the display's `CGDisplayBounds`,
  so the phone does not need to know the Mac's resolution. `CGEvent` posts
  mouse moved/down/up/drag, right-click, pixel scrolling, named key codes (US
  layout), modifier flags, and Unicode text. Accessibility permission is
  required; without it the helper stays view-only. Gestures: one-finger drag =
  drag, one-finger tap = click, double-tap = double-click, two-finger tap =
  toggle zoom, pinch = zoom, two-finger pan = canvas pan when zoomed / wheel
  scroll when not.
- **Permissions.** `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`
  and `AXIsProcessTrustedWithOptions` prompt for the helper. The iOS permission
  card requests them and polls `/api/remote` until the status flips. The helper
  retries capture every 3 seconds while Screen Recording is not granted.
- **Startup gotcha.** Reading stdin with a blocking `FileHandle.read` parked a
  thread and made the first `SCShareableContent` request hang; `WireInput` now
  uses a `DispatchSourceRead` and hands commands to the main queue.
- **One viewer capture.** Every viewer shares one helper capture. Input is
  last-writer-wins; there is no controller/observer arbitration. The helper is
  stopped 8 seconds after the last viewer disconnects, but the process stays
  alive so permission identity and display state are reused.
- **Packaging.** During development `make hub` builds
  `.build/debug/OpenCodeBarRemoteHost`; `OPENCODEBAR_REMOTE_HOST` overrides the
  path and `OPENCODEBAR_REMOTE=0` disables the feature. A distributed build
  should ship the helper inside a signed `.app`/LaunchAgent so TCC attributes
  Screen Recording and Accessibility to OpenCodeBar rather than the terminal
  that launched the hub.
- **Follow-ups.** H.264/VideoToolbox instead of per-frame JPEG for lower
  bandwidth and smoother motion; clipboard sync; a Mac-app remote client (the
  models and `HubAPI` methods are shared); a display picker is wired but only
  exercised with one display; keyboard layout is US-only; multi-monitor
  coordinates assume one helper per capture; and a controller lock would make
  two phones safer. The iOS app keeps a frozen frame after capture stops, so a
  `streaming: false` banner would make that state clearer.

## Performance (2026-10-22)

A pass over both clients is documented in [`performance/before.md`](performance/before.md)
and [`performance/after.md`](performance/after.md), with a reproducible
microbenchmark (`make bench`).

- Both stores now cache derived feeds (running/recent sessions, ordered projects,
  per-project running rows, subagent counts, project names). Project ordering
  moved to `Models/ProjectOrdering.swift` and no longer filters the session list
  for every comparison.
- Usage series are built once per body, use string day keys instead of a
  formatter call per item, and are bucketed to ~120 bars for `1Y`/`All`.
- `Fmt.grouped` reuses one `NumberFormatter`.
- Shared skeletons (`Views/PerformanceViews.swift`) replace spinner-only loading
  states; conversations and long lists (including the Mac Live, Projects,
  settings-device, and project-session feeds) are lazy, recent/project lists page
  in 20-row chunks, and reaching the end of a conversation pages automatically.
- Event-driven refreshes are throttled, independent requests run concurrently,
  duplicate first-load requests were removed, and iOS pauses polling in the
  background. On-demand caches are bounded to 16 entries.
- The hub coalesces updates before fan-out (`eventThrottleMs`, 250 ms by
  default; Settings → Updates or `PATCH /api/settings`). Pending updates for the
  same session/type keep the latest copy, and streamed text/reasoning deltas are
  merged, so busy sessions send a handful of events per window instead of one
  per token.

Remaining performance follow-ups are listed in `performance/after.md`
(observable slices per screen, store-level chart caches, incremental message
updates, server-side activity snapshots, and Instruments/UI benchmarks).

## Local cache and incremental sync (2026-10-23)

The iOS app now has a local SQLite cache and no longer re-reads the full
session/project lists on every poll.

- `server/src/db.ts` records real session/project changes in `sync_log` with a
  monotonic revision (`PRAGMA user_version = 5`). `upsertSessions`,
  `upsertProjects` and `updateSessionUsage` use a change-detecting
  `ON CONFLICT … WHERE`, so identical poll results write nothing. Project
  removals append tombstones instead of `DELETE`-ing the table and reinserting
  it. The feed keeps the newest 50,000 changes and falls back to a full snapshot
  for older revisions.
- `GET /api/sync?since=<revision>` returns `full`, changed `sessions` and
  `projects`, `deletedSessions`/`deletedProjects`, and the always-complete
  `active` list. `GET /api/session/{id}/message?since=<ms>` returns cached
  messages created/updated after the client's newest message.
- `Sources/OpenCodeBarMobile/MobileDatabase.swift` stores sessions, projects,
  the newest 500 messages per opened session, global stats and Go usage as JSON
  blobs in `Application Support/OpenCodeBar/opencodebar.sqlite`. `MobileStore`
  hydrates from it before networking, applies `/api/sync` deltas, writes them
  back, and clears the cache when the paired hub URL changes. The session detail
  view renders cached messages, then asks for `since` deltas while running.
- History for the Usage charts comes from the synced session cache; the iOS
  `refreshHistory` no longer fetches `/api/session?limit=1000` every minute.

Follow-ups:

- **The Mac app still polls full lists.** `AppState` can adopt `/api/sync` and
  the same SQLite cache; it shares `HubAPI`, so the client side is small.
- **No cache controls or size readout on iOS.** A Settings row showing the cache
  size and a "Clear cached data" action would help when troubleshooting.
- **No background refresh.** The cache makes cold launches fast but does not
  update while the app is suspended; a `BGAppRefreshTask` would fill that gap.
- **The change feed is write-driven only.** A session whose `time.updated` does
  not move but whose cost/tokens change is caught by
  `session.usage.updated` only if the hub receives that event; the 60s slow poll
  also upserts the session. If that ever proves insufficient, add a periodic
  full reconcile on the client.

## Virtual machines (2026-10-25)

The **VMs** tab runs declarative NixOS guests on the hub host with Apple's
Virtualization.framework.

- `Sources/OpenCodeBarVZ/` is a second SwiftPM helper. It owns one VM, writes
  `runtime.json` with its pid and loopback control/serial ports, and speaks
  JSON-lines on the control port. The hub spawns one detached helper per guest
  and re-adopts it after a restart.
- `server/src/vms/` stores definitions under `~/.local/share/opencodebar/vms/`,
  generates `configuration.nix` + a flake, runs `nix build` for
  `system.build.images.raw-efi`, copies the image, and manages packages over
  SSH. `server/src/api/vm-socket.ts` proxies the serial console.
- The helper must be signed with `com.apple.security.virtualization`; plain
  SwiftPM binaries are not. `make vz-helper` (and `make hub`) ad-hoc signs it.
  Without the entitlement VZ reports “Invalid virtual machine configuration”.
- Guest networking uses VZ NAT (`192.168.64.x`), with no port forwarding. The
  hub discovers the DHCP address from `arp -an`, then the serial log, and uses
  SSH on port 22. The guest configuration uses `hvc0` (virtio console) and
  `ttyAMA0` consoles.
- The image build needs Nix and an `aarch64-linux` builder on the host. On an
  Apple silicon Mac that is normally `darwin.linux-builder`. The image builder
  runs a Linux VM inside the builder (`make-disk-image`), which can be slow
  without nested virtualization.

Follow-ups:

- **Prebuilt image fallback.** A downloaded NixOS `raw-efi` image would let
  users run a VM without Nix or a Linux builder, at the cost of a more
  imperative first-boot configuration. The current feature is declarative-only.
- **Snapshots and clones.** Virtualization.framework has save/restore state and
  `DiskImageKit` overlays on newer macOS versions. A clone command would make
  experimentation much safer than the current destructive rebuild.
- **Graphical console.** Add a VZ graphics device and a framebuffer/VNC path;
  today only the serial console and SSH are available.
- **Guest metrics without SSH.** A small vsock agent (or a Virtio serial
  channel) would remove the SSH dependency for CPU/memory/disk and let a guest
  that has no network still report health.
- **Package picker.** The package field takes raw nixpkgs attribute names. A
  search endpoint over `nix search`/`nixpkgs` options would prevent typos, and
  a JSON package manifest would allow arbitrary extra modules.
- **Apply progress.** `nixos-rebuild` output streams to the Config log, but the
  UI has no phase breakdown. Parsing the build output into steps would make
  long applies easier to follow.
- **Disk resize and channel changes.** Both currently require a rebuild.
  Resizing is possible on APFS by growing the image; changing the channel could
  update the flake lock and rebuild in place.
- **Other distros.** The provider layer is NixOS-specific. Ubuntu cloud images
  with cloud-init and a package layer could reuse the helper and lifecycle.
- **Helper distribution.** The helper is ad-hoc signed and found in `.build/`
  or `dist/`. A distributed build should embed it in the signed app bundle (or
  a signed helper bundle) and sign it with the same identity.
- **Serial console auth.** The helper's control and serial ports bind to
  loopback, and the hub token gates the WebSocket. A local process can still
  connect directly; a per-helper secret would close that gap.
- **Setup logs are retained.** Installer/helper output lives in
  `~/.local/share/opencodebar/vms/setup/`; each new job rotates the previous
  `nix.log`/`helper.log` to a timestamped file and keeps ten per step. The VMs
  tab's document button opens the latest log, and `GET /api/vms/setup/logs`
  lists the history. This survives a hub restart or a cleared in-memory job.
- **Setup runner edge cases.** The Nix installer is launched in Terminal.app as
  the hub user, not via an `osascript` root shell: macOS 27 SIP restrictions
  block `/etc/fstab` creation from a non-GUI process. The Terminal script tees
  output into the setup log and writes an exit status; the hub polls it.
  The installer's `vifs` step needs a TTY and a GUI session; direct root
  attempts failed with `vifs: error creating /etc/fstab` and then
  `touch: /etc/fstab: Operation not permitted`. Terminal.app supplies the
  required context. The runner opens a dedicated Terminal window, tees output
  into `vms/setup/nix.log`, and polls a small status file; Cancel closes that
  window. A previous attempt can leave a “Nix Store” APFS volume and
  `/etc/synthetic.conf` behind; the installer detects and reuses/cleans them.
  If the user cancels the sudo prompt, no status file is written and the job
  times out; use Cancel and retry. The Terminal launch path should be re-tested
  when the installer changes. `make vz-helper` is streamed the same way. The
  Linux builder is still a manual terminal command because it is a long-lived
  VM and cannot be a one-shot setup job.

## Next steps

- **Go plan limits: credits and extra usage.** The Usage tab now shows the
  rolling / weekly / monthly windows from
  `GET https://opencode.ai/zen/go/v1/usage`. The console's *Credits*,
  *Extra usage*, and *Auto-recharge* rows are **not** in that endpoint — the
  balance is only retrievable from a console server function (upstream issue:
  "Zen API: expose credit balance in GET /zen/go/v1/usage"). Revisit if the
  endpoint grows a balance field.
- **Controls: prompt and new sessions are in.** The Chat tab has a composer that
  sends prompts into the open conversation, and the Live tab (plus a project
  page on the Mac) can start a new session with an optional first message.
  Running sessions queue prompts. Still open:
  - Interrupt / stop a running session: `POST /api/session/{sessionID}/interrupt`.
  - A steer/queue toggle instead of always queueing while a session runs.
  - Open a session in the TUI or a Terminal window.
  - Add the new-session action to the iOS project detail page; it currently
    starts from the Live tab, because the Projects tab owns its navigation path.
- **Distribute properly** (optional): Developer ID signing + notarization so the
  app runs without the local ad-hoc signature. A hardened-runtime build also
  needs the `com.apple.security.device.audio-input` entitlement for dictation.

## Known polish items

- **OpenCode can keep two project records for one directory.** A legacy record
  (no VCS, 0 sessions) sits alongside the live one, so the Projects tab merges
  records by `canonical` path and keeps whichever has activity. Three such
  duplicates exist on this machine (`ai-tools`, `expo-tools`,
  `cisco-anyconnect`). Revisit if OpenCode ever merges them server-side.
- **Project analytics load per open.** Each opened project costs two requests
  (scoped stats and sessions), refreshed with the 60s cycle while its detail
  page stays open. Fine for a handful of projects; a bulk endpoint would be
  better if the list ever needs totals inline.
- **Project files shell out to git on each open.** `/api/project/{id}/files`
  runs `git ls-files` and `git status` per request and caps at 20k paths, which
  is fine for normal repos but would benefit from a short-lived cache (keyed by
  directory and index mtime) for very large work trees.
- **Session stats hydrate message history on first open.** `/api/session/{id}/stats`
  pages through up to 30 pages (8s timeout per page) before aggregating tool
  calls, so a very long session can take a few seconds. The response's
  `complete` flag drives the Stats tab's "loaded so far" notice.
- **Project tool failures are counts, not individual errors.** The stats API's
  `tools=detail` payload has per-tool failed counts but no error messages.
  Showing recent project-wide failures would mean scanning cached messages,
  which only covers sessions that have been opened.

- **Session detail view shows the newest message first.** It does not jump to
  the bottom on load, and refreshes in place, so a running session keeps
  streaming without yanking the scroll position. A "follow"/pause toggle would
  still be a nice addition for long-running sessions.
- **Prompts are numbered per loaded window.** Numbers count up from the oldest
  loaded prompt, so they shift after "Load earlier"; they could instead count
  from the true start of the session once full history is loaded.
- **Dictation is one-shot.** The mic streams until tapped again, and the
  recognizer finalizes the last words after a short delay. `SFSpeechRecognizer`
  can end a very long utterance on its own, which stops the button; an audio
  level meter and an automatic restart would make long prompts smoother.

- **Live activity depends on the event stream.** Rows fold
  `session.step.*`, `session.reasoning.*`, `session.text.*`,
  `session.tool.*`, `session.usage.*`, and `permission.*` events. After a
  reconnect, or for a session already running at launch, the snapshot is rebuilt
  from the newest 20 messages. A `todowrite` list set earlier than that window is
  not recovered; todo progress is shown only while the session is running.
- **Waiting-for-approval is best-effort.** `permission.asked` payloads have
  changed shape across OpenCode versions. The label falls back from `message` to
  `title` to `action · resource`.
- **Live activity is shown on the Live tab, the session header, and the
  Subagents tab.** The Projects tab's running list is still a single line;
  `ActivityLine` could be reused there if those rows grow a second line.
- **The subagent tree loads one level at a time.** Direct children come from
  `/api/session?parentID=…` (limit 50); deeper levels load when opened. There is
  no aggregate cost roll-up and no recursive prefetch, and a parent with more
  than 50 children shows the newest 50.
- **The step timer resets at each `session.step.started`.** Total session
  elapsed stays on the stats line, and a finished tool freezes its own timer
  until the next event arrives.

- **Plan limits redraw once a minute.** Rows re-render when the 60s poll lands,
  so the reset countdown can sit up to a minute stale. A `TimelineView` would
  tick it continuously if that ever matters.
- **The usage cache has no expiry.** `~/Library/Caches/OpenCodeBar/usage.json`
  is always preferred over an empty Usage tab, so a file untouched for weeks
  would still render (with its age in the stale notice). Consider hiding the
  tiles past some threshold instead.
- **Model chip truncates** long model IDs in the *Recent* list on the Live tab
  (e.g. `deepseek-v4.1-flash` competes with the project name and timestamp).
  Options: shrink the font, allow two lines, show a tooltip, or drop the variant.
- **"Today's steps" can read 0 late at night.** The stats `activity` array lags
  at the day boundary — the last entry reflects the previous day until the server
  rolls over. Options: compute today's steps locally from sessions, or relabel the
  tile as "latest day".
- **Heatmap scaling uses `max`**, so a single outlier day flattens all other
  cells. Consider a percentile cap or clamping the color scale.
- **Trend cost/tokens are grouped by session update day.** The stats API only
  exposes daily steps, so cost and token series come from the session list; a
  long session puts all of its spend on the day it was last updated. The charts
  fetch the newest 1,000 sessions, so very large histories would be truncated.
- **The "All" chart range is down-sampled.** Series longer than 120 points are
  bucketed into ~120 bars, so a multi-year range is readable and cheap to draw;
  the x axis represents a bucket rather than a single day.

## Environment observations

- **The Go inference key in `auth.json` is expired.** `~/.local/share/opencode/auth.json`
  holds an `opencode-go` key that the usage endpoint rejects with
  `401 {"code":"api_key_expired"}`. Replacing it means running
  `opencode auth login` and would change the credential OpenCode uses for
  inference, so OpenCodeBar no longer depends on it. The Usage tab reads a
  **console service-account key** (`oc_sk_…`, *Inference only*) from
  `~/.config/opencode/opencodebar.json` instead. Create one in Console →
  **Keys** → *Add Service Account* → *Add API Key*; it works against
  `/zen/go/v1/usage` and returns the same windows the console page shows.
  Service-account keys are shown once, so store them immediately.
- **`OPENCODE_GO_USAGE_URL`** overrides the usage endpoint,
  **`OPENCODE_GO_USAGE_KEY`** / **`OPENCODE_API_KEY`** override the key, and
  `~/.config/opencode/opencodebar.json` (`{"goUsageKey": "…"}`) provides one
  that survives GUI launches. `docs/screenshots/usage.png` is now captured
  from the live endpoint.
- **`~/.local/share/opencode/opencode.db` is unusually large (~3.7 GB,
  3,765,533,624 bytes).** OpenCodeBar does not read it — it uses the HTTP API
  only — but the size is worth investigating separately (candidates: `VACUUM`,
  or checking for retained snapshots / tool-output / WAL growth).
- Service discovery depends on `~/.config/opencode/service.json` and the
  `opencode` CLI. Both were confirmed present and working on this machine
  (OpenCode v2.0.32).
- **Port 8787 was already taken on this machine** by an unrelated
  `node server/index.mjs`, so the hub was run with
  `OPENCODEBAR_HUB_PORT=8788`. The hub writes the port it actually bound into
  `~/.config/opencode/opencodebar-hub.json`, and both clients read it from
  there, so any free port works. `make hub` uses 8787 by default.
- **Hub state lives in `~/.local/share/opencodebar/hub.sqlite`** (WAL mode) and
  the generated connection file is `~/.config/opencode/opencodebar-hub.json`
  (mode 0600). Both are safe to delete; the hub recreates them and the token
  changes.
- **Quick tunnels were verified on this machine with `cloudflared 2026.10.1`
  and the iPhone on 5G.** The tunnel record is
  `~/.config/opencode/opencodebar-hub-tunnel.json` (mode 0600) and is removed
  when `Scripts/hub-tunnel.sh` exits. `cloudflared` is at
  `/opt/homebrew/bin/cloudflared`.
- **Nix 2.35.4 is now installed on this machine.** The app's setup runner had
  to switch from an `osascript` root shell to Terminal.app: macOS 27 marks the
  `/etc` symlink SIP-restricted, so creating `/etc/fstab` fails even as root
  (`vifs: error creating /etc/fstab`, then `touch: /etc/fstab: Operation not
  permitted`). Running the installer in a GUI Terminal session works; the hub
  tees its output into the setup log and polls a status file. The installer
  enabled only `nix-command`, so the Linux-builder command needs
  `--extra-experimental-features 'nix-command flakes'`. `/nix` is mounted from
  the new “Nix Store” APFS volume. The Linux builder still requires a sudo
  prompt in Terminal.
- The hub, helper, API, tests, and both apps were verified; the image build path
  was exercised with an injected Nix and a fake image. A real NixOS image build
  still needs the Linux builder running.
- **Virtualization.framework requires the `com.apple.security.virtualization`
  entitlement even for a non-sandboxed CLI.** An unsigned `swift build`
  produces a helper that fails configuration with “Invalid virtual machine
  configuration. The process doesn’t have the … entitlement.” `make vz-helper`
  (and `make hub`) ad-hoc signs it; `codesign -d --entitlements -` confirms it.
  A runtime probe with a dummy raw disk reached VZ `running` after signing and
  stopped cleanly when the firmware found no bootloader.
- **VZ NAT and the console.** The guest gets a `192.168.64.x` DHCP address with
  no host port forwarding, so the hub discovers it from `arp -an` and the serial
  log. The VZ virtio console is `hvc0`; the generated NixOS config sets both
  `console=hvc0` and `console=ttyAMA0` and imports `profiles/qemu-guest.nix`
  for the virtio initrd modules.
- **The six-tab iOS dock is a custom bar.** UIKit wraps a sixth `TabView` item
  in “More”, so VMs is rendered outside the five-item `TabView` while the custom
  dock still presents it as a top-level tab. The Mac tab bar also needed a
  smaller font and `lineLimit(1)` to fit six labels in the 400 pt panel.
- **Screenshot pairing.** Debug iOS builds accept
  `OPENCODEBAR_HUB_URL`/`OPENCODEBAR_HUB_TOKEN` from the environment so
  simulator screenshots can pair without the system URL confirmation. The
  `OPENCODEBAR_OPEN_VM` flag opens a VM after the first fetch.

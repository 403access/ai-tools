# Notes

Working notes for OpenCodeBar: follow-ups, known polish items, and environment
observations. Last updated 2026-10-21.

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
- **iOS distribution.** The repo builds for the simulator only (no team,
  no asset catalog, no App Store signing). A real device needs a development
  team and an app icon; `NSAllowsArbitraryLoads` should become a scoped ATS
  exception (or an HTTPS tunnel) before any store build.
- **Remote access.** The hub binds `0.0.0.0` with a Bearer token. For use away
  from home, prefer a tunnel (Tailscale/Cloudflare) and
  `OPENCODEBAR_HUB_HOST=127.0.0.1` rather than exposing the port.
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
- **iOS extras.** Home Screen widget for active sessions, Live Activity for a
  running session, and background refresh would make the phone more useful
  without opening the app.
- **Website.** `docs/index.html` still describes the macOS-only app; it should
  gain the iOS screenshots and a short hub section.

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
  app runs without the local ad-hoc signature.

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
- **The "All" chart range uses one bar per day.** With years of history the bars
  become sub-pixel; bucket by week or month once the range passes a threshold.

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

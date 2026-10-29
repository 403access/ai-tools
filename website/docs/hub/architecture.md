---
title: Architecture
sidebar_position: 1
---

# Hub architecture

OpenCodeBar Hub fits between the OpenCode service and the native apps.

```text
OpenCode service (loopback, Basic auth)
          │  REST + SSE
          ▼
OpenCodeBar Hub (Bun + SQLite, Bearer auth)
          │  cached REST + live events
    ┌─────┴─────┐
    ▼           ▼
 macOS app   iOS app
```

## Why a hub?

OpenCode is a client-server system. Its service listens on loopback and uses
HTTP Basic auth. A phone cannot reach that loopback socket, and a menu bar app
that talks to OpenCode directly loses history when the service restarts or moves
ports.

The hub solves both problems:

- It discovers the local service and speaks Basic auth to it.
- It exposes a stable, Bearer-authenticated API to clients.
- It caches sessions, projects, messages, changes, stats, and usage in SQLite.
- It forwards the live event stream so both apps update together.

## Discovery

The hub finds OpenCode using, in order:

1. `~/.config/opencode/service.json`
   (or `$XDG_CONFIG_HOME/opencode/service.json`) for the password.
2. `opencode service status` for the URL.
3. `lsof` for the listening process.
4. The OpenCode server log.

Overrides: `OPENCODEBAR_OPENCODE_URL` / `OPENCODE_SERVICE_URL` and
`OPENCODE_SERVICE_PASSWORD`.

## Polling

Read endpoints run on three cadences:

| Cadence | Default | What runs |
| --- | --- | --- |
| Fast | 5s | Sessions and active state |
| Slow | 60s | Projects, history, stats, usage |
| Usage | 60s | Go plan limits |

All values are configurable. See [Configuration](configuration.md).

## Event folding

The hub subscribes to OpenCode's `/api/event` SSE stream and forwards events to
every connected client. Before delivery it folds pending updates for one window
(250 ms by default, tunable in Settings → Updates): repeated events for the same
session/type keep only the latest copy, and streamed text/reasoning deltas keep
their combined text. It also folds events into a per-session activity snapshot:

- `session.step.*`
- `session.reasoning.*`
- `session.text.*`
- `session.tool.*`
- `session.usage.*`
- `permission.*`

That snapshot is what session headers and widgets show: current tool,
reasoning, todos, subagents, cost, elapsed time, and tokens. If the stream is missed, the newest
messages are read back to rebuild the snapshot.

The hub also emits `hub.*` notices (`hub.connected`, `hub.sessions`,
`hub.stats`, `hub.usage`) so clients know when cached data changed.

## Cached reads

Sessions, projects, messages, changes, stats, and usage are stored in
`~/.local/share/opencodebar/hub.sqlite` in WAL mode. When OpenCode stops or
restarts on a new port, the hub keeps serving the cache and reconnects when the
service returns.

Message history is cached the first time a session is opened, so paging back
works offline. Changes mirror the `metadata.files` patches found in cached
messages, so they survive an OpenCode restart.

## Incremental sync

The hub records every real session and project change in a `sync_log` with a
monotonic revision. Identical poll results are skipped, so a quiet hub writes
nothing. `GET /api/sync?since=<revision>` returns only the rows (and deletion
tombstones) after that revision; the first request, a reset hub, or a revision
older than the retained window gets a full snapshot instead. Clients store the
revision with their local copy and send it on the next poll.

The iOS app keeps its own SQLite cache in
`Library/Application Support/OpenCodeBar/opencodebar.sqlite`: sessions,
projects, the newest 500 messages per opened session, stats, and usage. It
renders that snapshot on launch, then applies deltas from `/api/sync` and writes
them back. Session detail pages show cached messages immediately and ask for
`message?since=<newest>` while a session runs, instead of refetching the whole
window. Pairing a different hub clears the cache so the two servers never mix.

## Project files

`/api/project/{id}/files` reads the project folder directly, so it reflects
the current disk state rather than the message cache. Inside a git work tree,
`git ls-files` supplies tracked and untracked-but-not-ignored paths and
`git status --porcelain` marks added, modified, deleted, and renamed files.
Other folders fall back to a recursive walk that skips common build and cache
directories. The response is capped at 20,000 paths and reports `truncated`
when it is shortened.

## Git

`/api/project/{id}/git` and `/api/session/{id}/git` read the work tree directly
on the hub's machine, the same way the file browser does. The project route runs
`git for-each-ref` and `git log --all --date-order` so branches, tags, and every
reachable commit come back with parent links; the clients use those links to
draw the lane graph. The session route reuses the repository summary and lists
commits whose committer time falls inside the session's created/updated window.

Both routes cap their commit list (2,000 by default, 20,000 maximum), report the
uncapped `total`, and return `null` instead of an error when the directory is
not a git work tree. Git commands run with a short timeout so a broken or huge
repository cannot stall the API.

## Project icons

`/api/project/{id}/icon` finds the icon a project already ships with, so the
project list and detail page show real app artwork instead of a folder glyph.
It prefers Xcode `AppIcon` asset catalogs and `.icns` bundles, then Apple touch
icons, favicons, icons, and logos, ignoring screenshots and build output. Large
images, SVG, ICO, and icon bundles are rendered to a bounded PNG with macOS
`sips` when it is available, and the result is cached for five minutes. The
route returns an `ETag` with a one-hour cache lifetime, or `404` when the folder
has no usable artwork; clients then fall back to the folder glyph.

## Session stats

Project and global stats come from OpenCode's stats API with `tools=detail`,
which adds per-tool succeeded/failed/unfinished counts and median durations.
Sessions have no stats endpoint upstream, so `/api/session/{id}/stats` derives
them from cached messages: tool parts are indexed by name and outcome, and the
first request pages through up to 30 pages of history. The response reports
whether history is complete.

## Trends

Steps come from the stats API's daily activity. Cost and tokens are grouped from
the full session list by the day each session was last updated. Project pages
use the same series scoped to one project.

## Writes

The apps can create sessions, send prompts, and pause, stop, or continue work.
The hub forwards these to OpenCode:

- `POST /api/session` creates a session.
- `POST /api/session/{id}/prompt` sends a prompt, optionally with
  `delivery: "steer" | "queue"`.
- `POST /api/session/{id}/pause` interrupts the turn and holds the session until
  a deadline.
- `POST /api/session/{id}/stop` interrupts the turn and holds it indefinitely.
- `POST /api/session/{id}/continue` clears the hold and sends `continue`.

Pause and stop state lives on the hub's session row, so it survives a hub
restart. The hub continues timed pauses from its fast loop. OpenCodeBar does not
delete sessions.

## Upstream endpoints

The hub reads from OpenCode:

- `/api/info`
- `/api/session`
- `/api/session/active`
- `/api/session/{id}`
- `/api/session/{id}/message`
- `/api/project`
- `/api/experimental/session/stats`
- `/api/event`

It writes through `POST /api/session`, `POST /api/session/{id}/prompt`, and
`POST /api/session/{id}/interrupt`.

Next: [configuration](configuration.md) and the [API reference](api.md).

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
every connected client. It also folds them into a per-session activity snapshot:

- `session.step.*`
- `session.reasoning.*`
- `session.text.*`
- `session.tool.*`
- `session.usage.*`
- `permission.*`

That snapshot is what the Live rows show: current tool, reasoning, todos,
subagents, cost, elapsed time, and tokens. If the stream is missed, the newest
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

## Project files

`/api/project/{id}/files` reads the project folder directly, so it reflects
the current disk state rather than the message cache. Inside a git work tree,
`git ls-files` supplies tracked and untracked-but-not-ignored paths and
`git status --porcelain` marks added, modified, deleted, and renamed files.
Other folders fall back to a recursive walk that skips common build and cache
directories. The response is capped at 20,000 paths and reports `truncated`
when it is shortened.

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

The apps can create sessions and send prompts. The hub forwards both to
OpenCode:

- `POST /api/session` creates a session.
- `POST /api/session/{id}/prompt` sends a prompt, optionally with
  `delivery: "steer" | "queue"`.

OpenCodeBar does not stop, interrupt, or delete sessions.

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

It writes through `POST /api/session` and
`POST /api/session/{id}/prompt`.

Next: [configuration](configuration.md) and the [API reference](api.md).

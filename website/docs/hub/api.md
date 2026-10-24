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

## Authentication

Every endpoint except `GET /api/ping` requires the Bearer token:

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
| `GET` | `/api/devices` | Connected devices |
| `GET` | `/api/settings` | Tunable hub settings |
| `PATCH` | `/api/settings` | Update the event throttle |

`/api/settings` returns the coalescing window applied to event-stream updates:

```json
{
  "data": {
    "eventThrottleMs": 250,
    "eventThrottleMinMs": 0,
    "eventThrottleMaxMs": 5000
  }
}
```

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

### Sessions

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/session` | List cached sessions |
| `POST` | `/api/session` | Create a session |
| `GET` | `/api/session/active` | Active session map |
| `GET` | `/api/session/{id}` | One session |
| `GET` | `/api/session/{id}/message` | Paged messages |
| `GET` | `/api/session/{id}/children` | Child sessions |
| `GET` | `/api/session/{id}/changes` | File patches |
| `GET` | `/api/session/{id}/stats` | Derived session stats |
| `GET` | `/api/session/{id}/pending` | Prompts admitted but not delivered |
| `DELETE` | `/api/session/{id}/pending/{inputID}` | Withdraw one queued prompt |
| `POST` | `/api/session/{id}/prompt` | Send a prompt |

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

### Projects

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/project` | All projects |
| `GET` | `/api/project/{id}` | One project |
| `GET` | `/api/project/{id}/changes` | Aggregated project changes |
| `GET` | `/api/project/{id}/files` | Project files with git status |
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

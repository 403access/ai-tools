# OpenCodeBar

A native macOS menu bar app that shows what your [OpenCode](https://opencode.ai)
background service is doing — at a glance, without leaving your current window.

The menu bar item displays a terminal glyph and, when sessions are running, the
number of active sessions. Clicking it opens a panel with **live** activity and
a **usage** overview.

![Live tab](docs/screenshots/live.png)
![Usage tab](docs/screenshots/usage.png)

## Features

**Live**
- Running sessions update in real time via OpenCode's SSE event stream, each with
  a pulsing indicator, project, model, agent, elapsed time, and token count.
- Recent sessions with project, model, relative time, cost, and tokens.

**Usage**
- OpenCode Go plan limits: rolling (5h), weekly, and monthly consumption as
  percentage bars with reset countdowns, read from the Go usage API. Hidden
  when no Go key is configured.
- Summary tiles: streak, active days, today's steps, prompts, sessions, total
  cost, tokens, tool calls, and subagents.
- A GitHub-style activity heatmap of daily agent steps.
- Token mix (input / output / reasoning / cache read / cache write).
- Per-model breakdown with steps and cost.
- Tool call success/failure summary.

The app is **monitor-only**: it never starts, stops, or modifies sessions.

## How it works

OpenCode runs a client-server architecture. Interfaces such as the TUI talk to a
background service that listens on loopback and is protected by HTTP Basic auth.

OpenCodeBar:

1. Reads the service password from `~/.config/opencode/service.json`
   (or `$XDG_CONFIG_HOME/opencode/service.json`).
2. Discovers the service URL with `opencode service status`, falling back to
   `lsof` and the server log.
3. Polls a few read-only endpoints and subscribes to `/api/event` for instant
   updates. If the service restarts on a new port, the app rediscovers it
   automatically.

Endpoints used: `/api/info`, `/api/session`, `/api/session/active`,
`/api/session/{id}`, `/api/project`, `/api/experimental/session/stats`, and
`/api/event`.

For Go plan limits the app additionally calls the console's usage endpoint,
`https://opencode.ai/zen/go/v1/usage`, with the Go API key from `auth.json`
(or `$OPENCODE_API_KEY`). That data is not part of the local service API.

## Requirements

- macOS 14 (Sonoma) or later.
- Xcode or the Swift toolchain (`swift` on your `PATH`).
- OpenCode V2 running as the background service (`opencode service status`
  prints a URL).

## Build and run

```sh
make run        # build dist/OpenCodeBar.app and launch it
```

Other targets:

```sh
make build      # swift build (debug)
make app        # assemble dist/OpenCodeBar.app (release)
make preview    # open the panel in a normal window for design work
make icon       # regenerate the app icon
make clean      # remove build artifacts and dist/
```

The first build generates `Assets/AppIcon.icns` and ad-hoc signs the bundle.

To launch at login, add `dist/OpenCodeBar.app` in **System Settings → General →
Login Items**.

## Website

A static landing page lives in [`docs/`](docs/index.html) and uses the same
screenshots referenced above. It is plain HTML/CSS with a small progressive-
enhancement script — no build step.

```sh
open docs/index.html
```

To publish it with GitHub Pages: **Settings → Pages → Source: Deploy from a
branch → `main` / `/docs`**. It is then served at
`https://403access.github.io/ai-tools/`.

## Project layout

```
Sources/OpenCodeBar/
  OpenCodeBarApp.swift      MenuBarExtra scene
  main.swift                entry point (also handles --preview)
  AppState.swift            observable state, polling, derived data
  Core/
    ServiceDiscovery.swift  password + URL discovery
    OpenCodeAPI.swift       async HTTP client
    GoUsageClient.swift     Go plan usage (console endpoint)
    EventStream.swift       SSE subscription with reconnect
  Models/Models.swift       Codable models for the API
  Views/                    SwiftUI panel, tabs, heatmap, components
  Preview/PreviewRunner.swift
Scripts/
  build-app.sh              assemble the .app bundle
  make-icon.swift           generate the app icon
```

## Development notes

- `--preview` runs the panel in a regular window instead of the menu bar
  popover, which makes screenshots and layout iteration easy.
  `--preview --tab usage` opens the Usage tab directly.
- `--screenshot <path>` renders the panel offscreen to a PNG and exits.
  `--screenshot out.png --scale 2 --tab usage` produces a 2x image for the
  website and README.
- The menu bar glyph uses SF Symbols (`terminal` / `terminal.fill`).
- `OPENCODE_GO_USAGE_URL` points the Go limits client at a different URL, which
  is how the Plan limits UI is exercised without a live Go key.
- `OPENCODE_API_KEY` overrides the Go API key read from `auth.json`.

## Limitations

- macOS only.
- Monitor-only by design; it does not control sessions.
- Relies on the local OpenCode service; when the service is stopped the panel
  shows an offline state and reconnects automatically.
- Go plan limits come from an undocumented console endpoint. Credits, the
  auto-recharge setting, and extra usage are console-only and are not shown.

See [NOTES.md](NOTES.md) for follow-ups and known polish items.

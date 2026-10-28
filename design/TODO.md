# OpenPencil design mirror — todo

Live checklist for the OpenPencil project. Keep it in sync with
[`ROADMAP.md`](ROADMAP.md) after each build pass.

Legend: `[x]` done · `[~]` in progress · `[ ]` planned

## Foundations

- [x] Create `design/OpenCodeBar.fig` in OpenPencil
- [x] Page skeleton (13 pages)
- [x] Design tokens: dark and light palettes from `Views/Theme.swift`
- [x] Type scale, spacing, radii
- [x] Core components: card, chip, pill, section header, stat tile, notice,
      empty state, bar, icon button
- [x] Navigation: panel tabs, mobile dock, status bar, footer

## macOS

- [x] Cover: menu bar item, left/right click behaviour
- [x] Panel shell and navigation
- [x] Live: running rows (thinking, tool, todo, subagent)
- [x] Live: recent rows, filters, grouping
- [x] Live: empty and loading
- [x] Tasks: board, filters, labels, actions
- [x] Tasks: Queued column, start-now/remove actions, hidden Done by default
- [x] Tasks: empty filters and no tasks
- [x] Tasks: queued column and "Show done" filter
- [x] New session sheet
- [x] Project picker sheet
- [x] Model picker sheet
- [x] Retry turn / fork sheet
- [x] Pause sheet
- [x] Settings: devices, server, power, pairing, developer
- [x] Session: conversation, stats, changes, prompts, git, subagents
- [x] Session: failed turn, paused, stopped, queued prompts, fork header
- [x] Projects: list, search, empty
- [x] Project detail: overview, stats, changes, files, git, sessions
- [x] Usage: overview, activity, breakdown, tools, no Go key, stale
- [x] System: machine, performance, memory, storage, network, software,
      processes, now playing, terminals, files
- [x] VMs: list, empty, unavailable, setup, logs, detail, console, packages,
      builder

## iOS

- [x] Live, Tasks, Projects, Usage, Settings
- [x] Tasks: Queued column, start-now/remove actions, hidden Done by default
- [x] Session detail and all tabs
- [x] Project detail and search
- [x] Pairing and device detail
- [x] Host dashboard and focused pages
- [x] Remote desktop: connected, permissions, view-only
- [x] Terminals, files, app detail
- [x] VMs and builder
- [x] Widgets: Live and Usage, small/medium/large
- [x] iPad layout
- [x] Light appearance

## Rendering fixes

- [x] Rebuild pages 05 and 07 as independent top-level frames
- [x] Replace percentage-height performance bars with pixel rectangles
- [x] Remove zero-size title-bar placeholders

## Cross-cutting

- [x] States page: empty, loading, error, stale, offline, permission
- [x] Architecture: diagram, request flow, API, data model, storage, security
- [x] Roadmap page
- [x] Coverage matrix and documentation map
- [x] README project layout updated
- [x] Website project layout updated
- [x] `design/README.md` with rebuild instructions

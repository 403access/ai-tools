---
title: Screenshots
sidebar_position: 5
---

# Screenshots

The marketing site, README, and these docs share the images in
`docs/screenshots/`. Copies live in `website/static/img/screenshots/` so the
Docusaurus build is self-contained.

## Regenerate everything

```bash
make shots
```

This builds the Mac app, renders 2× PNGs into `docs/screenshots/`, and copies
them into `website/static/img/screenshots/` for the docs site.

## Individual shots

```bash
swift build
.build/debug/OpenCodeBar --screenshot docs/screenshots/live.png --scale 2
.build/debug/OpenCodeBar --screenshot docs/screenshots/session.png --scale 2 --detail
.build/debug/OpenCodeBar --screenshot docs/screenshots/stats.png --scale 2 --detail --detail-mode stats
.build/debug/OpenCodeBar --screenshot docs/screenshots/changes.png --scale 2 --detail --detail-mode changes
.build/debug/OpenCodeBar --screenshot docs/screenshots/prompts.png --scale 2 --detail --detail-mode prompts
.build/debug/OpenCodeBar --screenshot docs/screenshots/projects.png --scale 2 --tab projects
.build/debug/OpenCodeBar --screenshot docs/screenshots/project-detail.png --scale 2 --tab projects --project-detail
.build/debug/OpenCodeBar --screenshot docs/screenshots/usage.png --scale 2 --tab usage
```

Use `--session <id>` to open a specific session. Combine it with
`--detail-mode subagents` to capture child sessions. Add `--terminal` to render
the first OpenCode terminal instead of the panel, or `--host-terminal` for the
first Terminal.app tab mirror; start one first, since the harness only renders
a terminal that the hub already lists.

:::note
Stats and Changes hydrate history on their first request. Open those tabs once,
or keep the hub cache warm, if a shot would otherwise capture the loading state.
:::

## Preview mode

```bash
make preview
make preview --args --tab usage
```

`--preview` renders the panel in a regular window for layout work.

## iOS screenshots

The iOS app reads debug-only environment variables from `simctl`:

```bash
SIMCTL_CHILD_OPENCODEBAR_TAB=usage \
  xcrun simctl launch booted dev.opencodebar.mobile

SIMCTL_CHILD_OPENCODEBAR_OPEN_SESSION=running \
  xcrun simctl launch booted dev.opencodebar.mobile

SIMCTL_CHILD_OPENCODEBAR_DETAIL_MODE=changes \
  xcrun simctl launch booted dev.opencodebar.mobile
```

- `OPENCODEBAR_TAB` — `live`, `projects`, `usage`, `settings`
- `OPENCODEBAR_OPEN_SESSION` — `running` or a session id
- `OPENCODEBAR_OPEN_PROJECT` — project id or path
- `OPENCODEBAR_DETAIL_MODE` — `stats`, `changes`, `prompts`, `subagents`

## Copy into the docs site

`make shots` copies the images automatically. To copy them manually:

```bash
cp docs/screenshots/*.png website/static/img/screenshots/
```

The README and marketing page use `docs/screenshots/` directly.

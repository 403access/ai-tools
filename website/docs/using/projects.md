---
title: Projects
sidebar_position: 3
---

import Figure from '@site/src/components/Figure';

# Projects

The **Projects** tab lists every project OpenCode has run in. Running projects
come first, then the most recently active.

<Figure src="/img/screenshots/projects.png" alt="Projects tab with project icons, running counts, and paths" caption="Search and pull-to-refresh are available on iOS; duplicate records for one directory are merged." />

## Project detail

<Figure src="/img/screenshots/project-detail.png" alt="Project detail with an Overview tab showing running sessions and at-a-glance stats" caption="Overview keeps running work and recent sessions together; Stats, Changes, Files, Git, and Sessions have their own tabs." />

Select a project to open its detail page. The name, path, and quick actions
stay pinned at the top, and the content is split into tabs so each kind of
information gets its own screen instead of one long scroll:

- **Overview** — at-a-glance steps, cost, tool calls, failures, tokens, and
  streak, followed by running sessions and the six most recent sessions.
- **Stats** — an interactive daily **Trend** chart for steps, cost, or tokens
  over the last 30 / 90 / 365 days or all time, scoped to the project, plus
  tool reliability and model mix.
- **Changes** — patches written by the project's newest sessions, grouped by
  session and file, revealed in pages of 20 files.
- **Files** — every file in the project folder, including untracked files, with
  git working-tree status for added, modified, and deleted files. Switch
  between **All** and **Changed**, or filter by path. The layout button swaps
  the flat list for a collapsible folder tree; collapsed folders show how many
  changed files they contain. Folders that are not git work trees still list
  their files, without status.
- **Git** — the repository's current branch, HEAD, working-tree state, local
  branches, tags, and the full commit graph across every ref. Commits keep
  their parent links, so merges and side branches are drawn as a lane graph
  instead of a flat list. Non-repository folders show an empty state.
- **Sessions** — every session in the project with its cost and time, revealed
  in pages of 50.

Tool reliability shows total calls plus per-tool succeeded, failed, and
unfinished counts with median durations. On iOS, the same sections appear on a
single scrolling project page, including Git.

The Git view is read directly from the project folder by the hub. It includes
all reachable commits across local refs up to the response cap, plus each
branch's upstream and ahead/behind offsets. A folder that is not a git work
tree shows an empty state rather than an error.

## Quick actions

On macOS:

- open the project in **Finder**,
- open a **Terminal** at the project directory,
- copy the project path,
- start a new session in the project.

On iOS, use the project page's session rows and start new work from the Live
tab.

## Search

The iOS Projects tab has a search field. The hub also exposes
`GET /api/search?q=…` for clients that want to search session titles and
projects.

## Project icons

Project rows and the project detail header show the icon the project already
ships with: an Xcode **AppIcon** asset, an `.icns` bundle, an Apple touch icon,
favicon, or logo. The hub finds the artwork inside the project folder, renders
large artwork and icon-bundle formats to a bounded PNG, and serves it to both
apps; folders with no usable artwork keep a folder glyph. The same icon appears
on macOS and iOS.

## Duplicate directories

OpenCode can sometimes keep a legacy project record next to the live one for the
same directory. OpenCodeBar merges records by canonical path and keeps the one
with activity, so a project does not appear twice.

## Refresh behaviour

Project analytics are fetched when the detail page opens and refreshed while it
stays open. Scoped stats and sessions are requested per project rather than
derived from the global session list. Project changes hydrate the newest ten
sessions by default; use `?sessions=` on the API to widen that window.

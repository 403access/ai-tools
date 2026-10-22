---
title: Projects
sidebar_position: 3
---

import Figure from '@site/src/components/Figure';

# Projects

The **Projects** tab lists every project OpenCode has run in. Running projects
come first, then the most recently active.

<Figure src="/img/screenshots/projects.png" alt="Projects tab with running counts and paths" caption="Search and pull-to-refresh are available on iOS; duplicate records for one directory are merged." />

## Project detail

<Figure src="/img/screenshots/project-detail.png" alt="Project detail with running sessions, trends, analytics, and file counts" caption="Running work, scoped trends, analytics, changes, and tool reliability." />

Select a project to see:

- **Running** sessions with elapsed time, tappable into the session view.
- **Trend** — an interactive daily chart for steps, cost, or tokens over the
  last 30 / 90 / 365 days or all time, scoped to the project.
- **Analytics** — steps, prompts, sessions, cost, tokens, streak, and model mix.
- **Changes** — patches written by the project's newest sessions, grouped by
  session and file.
- **Tool reliability** — total calls plus per-tool succeeded, failed, and
  unfinished counts with median durations.
- **Recent sessions** with their cost and time.

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

## Duplicate directories

OpenCode can sometimes keep a legacy project record next to the live one for the
same directory. OpenCodeBar merges records by canonical path and keeps the one
with activity, so a project does not appear twice.

## Refresh behaviour

Project analytics are fetched when the detail page opens and refreshed while it
stays open. Scoped stats and sessions are requested per project rather than
derived from the global session list. Project changes hydrate the newest ten
sessions by default; use `?sessions=` on the API to widen that window.

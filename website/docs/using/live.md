---
title: Live sessions
sidebar_position: 1
---

import Figure from '@site/src/components/Figure';

# Live sessions

The **Live** tab is the default view. Running work appears first, followed by
recent sessions.

<Figure src="/img/screenshots/live.png" alt="Live tab with running and recent sessions" caption="Running sessions stream in over SSE; recent sessions sit below." />

## Running sessions

Each row shows:

- the session title, project, model, agent, and a pulsing running indicator;
- the current tool and its command or path;
- streaming reasoning or text, todo progress, and running subagent count;
- live cost, elapsed time, and token count.

OpenCode events (`session.step.*`, `session.reasoning.*`, `session.text.*`,
`session.tool.*`, `session.usage.*`, and `permission.*`) are folded into a
per-session activity snapshot. Cost and tokens move as usage events arrive
instead of waiting for the next poll.

New rows animate in at the top. When the stream is missed — on launch or after a
reconnect — the newest messages are read back to rebuild the snapshot,
including the latest todo list.

## Recent sessions

Recent rows show the project, model, relative time, cost, and tokens. Select a
row to open the full [session view](session.md).

### Filter recent sessions

Both apps have filter chips in the Recent header:

- **Project** — all projects, or one project. Duplicate project records for the
  same directory are matched by canonical path, so they filter as one.
- **Date** — all time, today, last 7 days, or last 30 days.

Filters apply only to the recent list, not to running sessions. When no rows
match, the empty state suggests trying another project or range.

## Start a new session

Use **New** on the Live tab (or the plus button on a project page):

1. Pick a project directory, or type a custom path.
2. Optionally give the session a title.
3. Optionally type or dictate a first message.
4. Create the session.

The new session opens immediately, and the first message is sent in the same
step. You can fix a failed first message and retry without creating a second
session.

:::note
The apps can start sessions and send prompts, but they do not stop, interrupt,
or delete them. Prompts sent to a running session are queued behind the current
turn.
:::

## Menu bar count

On macOS the menu bar item shows the number of active sessions while work is
running. Click it to open the panel; the live state stays current while the
popover is open.

See [Session detail](session.md) for the conversation, stats, changes, prompts,
and subagents.

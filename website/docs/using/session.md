---
title: Session detail
sidebar_position: 2
---

import Figure from '@site/src/components/Figure';

# Session detail

Select any session on the Live tab or a project page to open it.

<Figure src="/img/screenshots/session.png" alt="Session conversation with reasoning, tool calls, and the composer" caption="The conversation keeps the newest message first and refreshes in place." />

## Tabs

| Tab | What it shows |
| --- | --- |
| **Chat** | The full conversation, newest message first |
| **Stats** | Prompts, steps, tool reliability, failures, files, and token mix |
| **Changes** | Every file the session wrote, with real patches and line counts |
| **Git** | The current branch, HEAD, working-tree state, and commits made during the session |
| **Prompts** | A prompts-only list with copy buttons |
| **Subagents** | Child sessions, shown when the session has any |

## Chat

The conversation is newest-first. **Load earlier** at the bottom pages back
through history. The view refreshes in place while the session runs without
yanking the scroll position.

Assistant text is shown directly. Reasoning and tool calls are collapsible.
Edit and write tool cards show the same diff as the **Changes** tab instead of
raw input JSON.

### Reply in the conversation

The composer at the bottom sends the next prompt into this session.

- A running session queues the message until the current turn finishes.
- Queued prompts appear above the composer, oldest first, with a **×** to
  withdraw one before the running turn claims it.
- The conversation refreshes as soon as the message is sent and again when the
  reply arrives.
- The microphone button dictates into the composer. The transcript stays
  editable before you send it. See [Voice input](voice.md).

### Failed turns and retries

If a provider call fails, OpenCode records the error on the turn. The Chat tab
shows a **Turn failed** card with the provider's message and HTTP status, and a
banner above it offers:

- **Retry here** — resends the same prompt in the current conversation so the
  turn can continue.
- **Retry options…** — opens a sheet where you can send `continue`, choose the
  destination (**This session** or **New fork**), and pick a model, variant, and
  agent before resending. The model browser has search, provider filters,
  sorting, and inline variant choices.

Retrying in this session keeps the failure in the conversation history. A fork
leaves the original session untouched and keeps only the history before the
failed prompt. A forked session's header links back to its source conversation,
and the source lists its forks. The header and **Session settings** disclosure
also show the agent, model, provider, variant, directory, and outcome that were
actually used.

### Models and data training

OpenCodeBar forwards prompts to OpenCode; it does not choose the provider or
change its data-use terms. New sessions use OpenCode's default model for the
directory, which may be a model that trains on request data. The app lists the
catalog OpenCode exposes and shows which model actually ran, but it cannot mark
or filter models by a provider's training policy because OpenCode does not
expose that metadata.

:::warning
Never enable **Allow paid endpoints that train on request data** just to make a
model work in OpenCodeBar. OpenCode CLI does not need that setting, and neither
do the apps. If a turn fails with the training error, choose a model whose
policy you accept — for example with **Retry options…** — or change your
OpenCode default model.
:::

OpenCodeBar never changes your OpenCode or Go workspace privacy settings. See
[Data training and model choice](../help/faq.md#will-opencodebar-enable-training-on-my-data)
for the short version.

## Stats

<Figure src="/img/screenshots/stats.png" alt="Session Stats tab with tool reliability and per-tool durations" caption="Stats are derived from cached messages and indexed tool calls." />

The Stats tab includes:

- prompts, steps, messages, subagents, cost, and duration;
- a reliability summary: total calls, succeeded, failed, unfinished;
- per-tool calls, failures, and median duration;
- recent failures with their errors;
- file impact: files touched, additions, deletions;
- input/output/reasoning/cache token mix.

Project and usage breakdowns request `tools=detail` from OpenCode's stats API.
Sessions have no upstream stats endpoint, so the hub derives their numbers from
cached messages. On the first open it may page through up to 30 pages of
history. If totals cover only the loaded window, the tab says so.

## Changes

<Figure src="/img/screenshots/changes.png" alt="Session Changes tab with a colour-coded diff" caption="Patches survive an OpenCode restart because the hub extracts them while caching messages." />

The Changes tab groups every patch written by the session by file. Each card
shows the added and removed line counts, a colour-coded diff, and a collapsible
preview for long patches. Repeated edits to one file are grouped. The layout
button swaps the diff cards for a collapsible file tree with per-file line
counts; tap a file in the tree to show its patch.

The hub reads the `metadata.files` patches that OpenCode attaches to edit/write
tool calls and stores them while caching messages, so they remain available
after the service restarts.

## Git

The Git tab shows the work tree around the session: current branch, HEAD
commit, upstream ahead/behind counts, and how many files have uncommitted
changes. Below that it lists every commit made while the session was active,
newest first, with the author and relative time.

The hub reads the session's directory directly with git, so the tab reflects
the current checkout rather than the message cache. Sessions opened outside a
git work tree, or without a directory, show a **Not a git repository** empty
state.

## Prompts

<Figure src="/img/screenshots/prompts.png" alt="Prompts-only list with copy buttons" caption="Prompts are numbered per loaded window; system and shell entries are labelled." />

The Prompts tab lists only what you sent, with a copy button on every entry.
Injected system and shell entries are labelled so they are easy to skip.

## Subagents

When a session has child sessions, a **Subagents** tab appears. Each child shows
its own live activity, outcome, cost, and time. Select one to drill in; **Back**
returns to the parent. Each level loads its own children with
`/api/session?parentID=…`.

## Deep links

The public URL scheme is for pairing: `opencodebar://pair?url=…&token=…`. There
is no public session URL. For automation and screenshots, the iOS debug build
accepts `OPENCODEBAR_OPEN_SESSION` (`running` or a session id) to open a session
on launch.

---
id: intro
title: OpenCodeBar documentation
slug: /
sidebar_position: 1
hide_table_of_contents: true
hide_title: true
---

import HomeHero from '@site/src/components/HomeHero';
import Figure from '@site/src/components/Figure';

<HomeHero />

OpenCodeBar is a native macOS app and an iPhone/iPad app for
[OpenCode](https://opencode.ai). On the Mac it runs in the menu bar and,
optionally, as a full desktop window. Both clients talk to **OpenCodeBar Hub**,
a small Bun + SQLite server that ingests your local OpenCode service and keeps
one shared, cached history.

<p className="lead">
Watch running sessions, read and reply in any conversation, start new work,
inspect the files a session changed, and track usage — without leaving the
window you are in.
</p>

<div className="featureGrid">
  <div className="featureCard">
    <h3>Live activity</h3>
    <p>Current tool, command or path, streaming reasoning, todos, subagents, cost, elapsed time, and tokens.</p>
  </div>
  <div className="featureCard">
    <h3>Prompt &amp; create</h3>
    <p>Reply in an open conversation, dictate a prompt, or start a session with an optional first message.</p>
  </div>
  <div className="featureCard">
    <h3>Stats &amp; changes</h3>
    <p>Per-session tool reliability, failures, file impact, token mix, and colour-coded diffs.</p>
  </div>
  <div className="featureCard">
    <h3>Projects</h3>
    <p>Running work first, then scoped trends, model mix, project changes, and tool reliability.</p>
  </div>
  <div className="featureCard">
    <h3>Usage</h3>
    <p>Go plan limits, streaks, activity heatmap, token mix, models, and tool success rates.</p>
  </div>
  <div className="featureCard">
    <h3>System</h3>
    <p>CPU, memory, disks, battery, network, now-playing media, processes, installed apps, Homebrew, developer tools, a read-only host file browser, and interactive terminals on the host.</p>
  </div>
  <div className="featureCard">
    <h3>Settings</h3>
    <p>Connected devices, hub health, sync, restart, data files, and one-click pairing.</p>
  </div>
</div>

## How the pieces fit

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

The hub discovers OpenCode, polls its read endpoints, folds the live event
stream into per-session activity, and writes everything into SQLite. The apps
read cached data from the hub, so history stays available when OpenCode is
stopped or moves to a new port.

## Start here

- [Requirements](getting-started/requirements.md) — what you need before the first build.
- [Install the hub](getting-started/install-hub.md) — start the server and get a pairing link.
- [Run the Mac app](getting-started/mac-app.md) — build, launch, and keep it in the menu bar.
- [Run the iOS app](getting-started/ios-app.md) — simulator or a physical iPhone/iPad.
- [Pair the apps](getting-started/pairing.md) — connect the phone to the hub.
- [Hub API reference](hub/api.md) — every endpoint, auth, and device headers.

## A closer look

<div className="screenshotGrid">
  <Figure src="/img/screenshots/live.png" alt="OpenCodeBar Live tab showing running sessions" caption="Live sessions on macOS" />
  <Figure src="/img/screenshots/ios-live.png" alt="OpenCodeBar Live tab on iOS" caption="The same activity on iPhone" />
  <Figure src="/img/screenshots/stats.png" alt="Session Stats tab with tool reliability and timings" caption="Per-session stats and tool reliability" />
  <Figure src="/img/screenshots/changes.png" alt="Session Changes tab showing a colour-coded diff" caption="File changes with real patches" />
</div>

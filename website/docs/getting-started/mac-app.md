---
title: Run the macOS app
sidebar_position: 3
---

import Figure from '@site/src/components/Figure';

# Run the macOS app

With the hub running, build and launch the menu bar app:

```bash
make run
```

This compiles the release binary, assembles and ad-hoc signs
`dist/OpenCodeBar.app`, and opens it. The first build also generates the app
icon.

To launch straight into the desktop window instead, use `make desktop`.

<Figure src="/img/screenshots/live.png" alt="OpenCodeBar Live tab on macOS" caption="Right-click the menu bar item to open the compact panel." />

## What you get

- A terminal glyph in the menu bar, with the number of active sessions while
  work is running.
- **Left-click** the icon for the full desktop window; **right-click** (or
  control-click) for the compact panel with **Live**, **Usage**, **Projects**,
  **System**, and **Settings**.
- Session detail pages, project detail pages, and a full conversation view.
- A footer with the active count and the last refresh time.

## Desktop window

OpenCodeBar can also run as a regular desktop app. Left-click the menu bar
icon, or turn on **Settings → App → Desktop window**. The same views move into
a resizable window with a persistent sidebar, a Dock icon, and an app menu; the
menu bar item keeps working alongside it.

When the window is wide enough, the list stays beside the page you are reading:
projects next to their project page, and projects → project → session as three
columns when you open a session from a project. Narrow windows fall back to the
single-page layout. The window remembers its size and position.

The setting is remembered, so the window reopens on the next launch. Closing
the window (or turning the setting off) returns OpenCodeBar to menu-bar-only
mode and removes the Dock icon. `make desktop` turns the setting on and
launches straight into the window.

The app reads `~/.config/opencode/opencodebar-hub.json` and connects
automatically. If you override the hub URL or token with environment variables,
see [Pairing and overrides](pairing.md).

## Rebuild and restart

```bash
make restart
```

`make restart` builds first and only stops the old instance if the build
succeeds, so a failed build leaves the current app running.

```bash
Scripts/restart.sh --no-build      # relaunch the existing bundle
CONFIG=debug Scripts/restart.sh    # rebuild a debug bundle instead
```

## Design and screenshots

```bash
make preview                       # panel in a normal window
make preview --args --tab usage    # open a specific tab
```

`--preview` is useful for layout work and screenshots. `make shots` regenerates
the images used by the website, README, and these docs.

## Launch at login

Add `dist/OpenCodeBar.app` in **System Settings → General → Login Items**. The
hub can be launched separately, for example with a `launchd` agent, if you want
the phone to reach it without keeping a terminal open.

## Build only

```bash
make build      # swift build (debug)
make test       # swift test
make app        # assemble dist/OpenCodeBar.app (release)
```

## Updating

```bash
git pull
make restart
```

The app is ad-hoc signed for local use. There is no Developer ID or
notarization setup in the repository.

Next: [run the iOS app](ios-app.md).

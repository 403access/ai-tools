---
title: FAQ
sidebar_position: 2
---

# FAQ

## Does OpenCodeBar send my data to a cloud service?

OpenCodeBar itself does not. The Mac app, iOS app, and hub run locally, and the
hub cache stays in `~/.local/share/opencodebar/hub.sqlite`. There is no
OpenCodeBar telemetry, analytics, or hosted relay. The only outbound OpenCodeBar
request is the optional Go usage lookup to OpenCode's console endpoint.

Prompts are different: they go through OpenCode to the model provider you have
configured there. That provider may log, retain, or train on request data
depending on its terms and your workspace settings. OpenCodeBar does not control
those policies. See [Will OpenCodeBar enable training on my data?](#will-opencodebar-enable-training-on-my-data).

## Will OpenCodeBar enable training on my data?

No. It never changes OpenCode, provider, or Go workspace privacy settings. Some
Go models require the workspace option **Allow paid endpoints that train on
request data**; do not enable it just to use OpenCodeBar. OpenCode CLI does not
need it, and neither do the apps.

Choose a model whose data-use policy you accept. After a failed turn, **Retry
options…** lets you continue in the same session or fork it, and pick a
different model, variant, and agent. You can also set a non-training model as
OpenCode's default for the directory.

## Why did a phone-created session use a model I don't use in the CLI?

New sessions use OpenCode's default model for that directory. The CLI may have a
session- or command-specific model selection that does not change that default.
The session header and **Session settings** disclosure show the model, provider,
variant, and agent that actually ran.

If the default is a model you do not want, change the default in OpenCode's
configuration for that project, or use **Retry options…** after a failed
turn to choose another model. OpenCodeBar will never enable a training opt-in to
make a model work.

## Does it stop or delete sessions?

It can stop work but not delete it. Use **Pause…** to hold a session for a
duration or until a clock time, or **Stop** to hold it until you press
**Continue**. Either action interrupts the current turn and removes the session
from the Running list. Paused and stopped sessions keep their history and show a
badge in the Recent list. **Continue** sends a new `continue` prompt, and typing
any prompt also releases the hold.

OpenCodeBar cannot delete sessions. A prompt sent to a running session is queued
by default and appears in the pending queue above the composer until it starts.

## Why doesn't the Mac app show up in Spotlight, Raycast, or Launchpad?

`make run` builds into `dist/`, which Raycast does not index, and every build
recreates that bundle. Run `make install` to place a registered copy in
`~/Applications`; Spotlight and Raycast then find it. Launchpad stays empty
because the app is a menu bar agent (`LSUIElement`) with no Dock icon.

## Can I use it without a Mac?

The iOS app needs a hub. The hub needs a machine that can run Bun and reach
OpenCode. That is normally a Mac, because OpenCode is running there.

## Can multiple phones connect?

Yes. Pair each device. The Mac's **Settings → Devices** list shows every client
with its platform and app version.

## Why does the phone lose its connection when I leave the Mac?

macOS sleeps an idle Mac, which stops the hub from answering. Turn on
**Settings → Power → Keep Mac awake** in the Mac app (or start the hub with
`OPENCODEBAR_PREVENT_SLEEP=1`). The hub then holds an idle-sleep assertion while
it runs. The display can still turn off, but closing the lid still sleeps the
Mac.

## Can I run more than one hub?

You can, but each hub owns one SQLite database and one OpenCode service. Point
each phone at the hub you want. Do not run two hubs against the same database.

## Where is the data stored?

- Hub cache: `~/.local/share/opencodebar/hub.sqlite`
- Hub connection: `~/.config/opencode/opencodebar-hub.json`
- Mac usage cache: `~/Library/Caches/OpenCodeBar/usage.json`
- OpenCode data: managed by OpenCode, not OpenCodeBar

## Can I delete the cache?

Yes. Delete `hub.sqlite` and restart the hub. It recreates the database and
rebuilds history from OpenCode. Deleting `opencodebar-hub.json` also generates a
new token, so the phone must pair again.

## Why is the newest message first?

Feeds are ordered most-recent-first. New messages and sessions animate in at the
top, and **Load earlier** at the bottom pages back through history. This keeps
the live state in view while a session runs.

## Can I use it away from home?

Use a private tunnel such as Tailscale, or run `make hub-tunnel` for a
Cloudflare quick tunnel, which needs no account and prints a public HTTPS URL.
The hub speaks plain HTTP, so do not expose its port directly to the internet.
You can bind to loopback and tunnel to it. See [Security](../hub/security.md).

## Does it work with OpenCode v1?

OpenCodeBar targets the OpenCode V2 service API. The hub depends on v2 endpoints
such as `/api/session/active`, `/api/experimental/session/stats`, and the SSE
event shapes.

## Can I change the port?

Yes:

```bash
OPENCODEBAR_HUB_PORT=8788 make hub
```

Without the environment variable, a busy port falls forward automatically. With
it set, a busy port is an error.

## Does the iOS app need App Store signing?

No. It builds for the simulator and installs on a physical device with an Apple
Development identity. There is no App Store distribution setup in the
repository.

## Are there Home Screen widgets or Live Activities?

There are two Home Screen widgets: **Live Sessions** and **Usage**, each in
small, medium, and large. Add them from the Home Screen's widget gallery after
pairing the app. Live Activities are not implemented yet. See
[Run the iPhone/iPad app](../getting-started/ios-app.md#home-screen-widgets).

## Why do credits not appear in Usage?

The Go usage endpoint does not return credits, extra usage, or auto-recharge.
Those values exist only in the console. See
[Go plan usage](../hub/go-usage.md).

## How do I contribute docs?

See [Documentation site](../development/docs-site.md). Add a page under
`website/docs/`, register it in `sidebars.js`, and run `make docs-build` before
opening a pull request.

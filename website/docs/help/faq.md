---
title: FAQ
sidebar_position: 2
---

# FAQ

## Does OpenCodeBar send my data to a cloud service?

No. The Mac app, iOS app, and hub run locally. The only outbound request is the
optional Go usage lookup to OpenCode's console endpoint. There is no
OpenCodeBar telemetry or hosted relay.

## Does it stop or delete sessions?

No. OpenCodeBar can start sessions and send prompts. It cannot interrupt, stop,
or delete them. A prompt sent to a running session is queued by default.

## Can I use it without a Mac?

The iOS app needs a hub. The hub needs a machine that can run Bun and reach
OpenCode. That is normally a Mac, because OpenCode is running there.

## Can multiple phones connect?

Yes. Pair each device. The Mac's **Settings → Devices** list shows every client
with its platform and app version.

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

Not yet. They are follow-up ideas in `NOTES.md`.

## Why do credits not appear in Usage?

The Go usage endpoint does not return credits, extra usage, or auto-recharge.
Those values exist only in the console. See
[Go plan usage](../hub/go-usage.md).

## How do I contribute docs?

See [Documentation site](../development/docs-site.md). Add a page under
`website/docs/`, register it in `sidebars.js`, and run `make docs-build` before
opening a pull request.

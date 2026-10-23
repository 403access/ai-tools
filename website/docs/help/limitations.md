---
title: Limitations
sidebar_position: 3
---

# Limitations

## Session controls

The apps can start sessions and send prompts, but they cannot interrupt, stop,
or delete a session. Prompts sent while a session is running are queued behind
the current turn (or steered if the client requests it).

## Hub dependency

The phone always needs a reachable hub for live updates. The iOS app still
renders its last local snapshot while the hub is unreachable, but new data
requires the hub. The Mac app uses the hub too, so without it you lose live
updates and cached history. The hub is a foreground Bun process unless you wrap
it in a launch agent.

## Go plan limits

Plan limits come from an undocumented console endpoint. Credits, extra usage,
and auto-recharge are console-only and are not shown.

## Cache growth

Every session opened is cached on the hub, and the changes table mirrors every
patch found in those messages. There is no hub retention policy yet; long-lived
installs may need to prune or recreate `hub.sqlite`. The iOS app keeps its own
cache and retains the newest 500 messages per opened session.

## Hydration windows

- Session stats page through up to 30 pages of history the first time they are
  requested. Very long sessions can take a few seconds and may report partial
  totals.
- Project changes hydrate the newest ten sessions by default. Use
  `?sessions=` or open older sessions directly to include them.

## Subagents

The subagent tree loads one level at a time. There is no recursive prefetch or
aggregate cost roll-up. A parent with more than 50 children shows the newest 50.

## Feeds and charts

- Cost and token trends are grouped by the day a session was last updated, not
  by individual messages.
- The full session list used for charts is capped on the hub (5,000 rows). The
  iOS app charts its incrementally synced session cache; the Mac app still
  fetches 1,000 sessions.
- The “All” chart range uses one bar per day; very long histories can look
  dense.

## Platform

- macOS 14+ and iOS 17+ only.
- The iOS app allows arbitrary HTTP loads because the hub is normally a plain
  HTTP LAN address. There is no App Store signing setup.
- The Mac app is ad-hoc signed; there is no Developer ID/notarization flow in
  the repository.

## Local network

The hub binds `0.0.0.0` by default. It is meant for a trusted LAN or a private
tunnel. It is not hardened for direct internet exposure. `make hub-tunnel`
provides an ephemeral Cloudflare HTTPS URL for cellular use; the URL changes on
each run and stops working when the process exits.

## Not implemented yet

- Live Activities.
- Interrupt/stop controls.
- A steer-versus-queue toggle in every client.
- Opening a session in the TUI or a terminal.
- A first-class project new-session action on iOS.

Home Screen widgets refresh on the schedule iOS gives them (usually every five
to fifteen minutes, less often in Low Power Mode); they are not a real-time
replacement for the open app.

See `NOTES.md` in the repository for the current follow-up list.

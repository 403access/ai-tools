---
title: Security
sidebar_position: 4
---

# Security

OpenCodeBar is designed for a trusted local network. It does not ship with a
cloud account, telemetry, or a hosted relay.

## Threat model

- OpenCode itself listens on loopback and uses HTTP Basic auth.
- The hub listens on `0.0.0.0` by default so a phone on the same LAN can reach
  it.
- Every hub request except `/api/ping` requires a Bearer token.
- The token is stored in `~/.config/opencode/opencodebar-hub.json` with mode
  `0600`, and on iOS in the app's local storage.

## The pairing link is a secret

The `opencodebar://pair?url=…&token=…` link and the QR code in the Mac's
Settings tab contain the hub token. Anyone with either can read and control your
OpenCode sessions while they are on the network. Share them only with your own
devices.

## Do not expose the hub directly to the internet

The hub speaks plain HTTP, not HTTPS. For access away from home, use a private
tunnel such as Tailscale or Cloudflare Tunnel, or keep
`OPENCODEBAR_HUB_HOST=127.0.0.1` and forward through a tunnel that terminates
TLS.

If you only use the Mac app, bind to loopback:

```bash
OPENCODEBAR_HUB_HOST=127.0.0.1 make hub
```

The phone then needs a tunnel or a reverse proxy.

## Firewall and local network permission

- macOS may ask whether OpenCodeBar can access the local network. Allow it.
- If the Mac firewall blocks incoming connections, allow the Bun process or the
  hub port.
- On iOS, Local Network permission is required to reach the Mac.

## Credentials

| Secret | Where it lives | Notes |
| --- | --- | --- |
| Hub token | `opencodebar-hub.json`, iOS app storage | Rotate by deleting the file and restarting the hub |
| OpenCode password | `~/.config/opencode/service.json` | Read by the hub, sent over loopback |
| Go usage key | env, `opencodebar.json`, or `auth.json` | Prefer a service-account, usage-only key |

Deleting `opencodebar-hub.json` and restarting generates a new token. The phone
must be paired again.

## iOS transport security

The iOS app allows arbitrary HTTP loads because the hub is normally a plain HTTP
address on the LAN. There is no App Store distribution or scoped ATS exception
configured in the repository yet. For a store build, use an HTTPS tunnel or add
a scoped exception.

## What OpenCodeBar does not do

- It does not stop, interrupt, or delete sessions.
- It does not upload your data to an OpenCodeBar service.
- It does not include analytics or telemetry.
- It does not bypass OpenCode's own auth; the hub authenticates to OpenCode
  using the local service credentials.

## Data removal

Deleting `~/.local/share/opencodebar/hub.sqlite` removes the hub cache. Deleting
`~/Library/Caches/OpenCodeBar/usage.json` removes the Mac's last-known usage.
Neither touches OpenCode's own data.

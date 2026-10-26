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
- Every hub request except the liveness probe (`/api/ping`) and the API
documentation (`/api/docs`, `/api/openapi.json`) requires a Bearer token. The
documentation exposes route shapes only, never cached data.
- The token is stored in `~/.config/opencode/opencodebar-hub.json` with mode
  `0600`, and on iOS in the app's local storage.

## The pairing link is a secret

The `opencodebar://pair?url=…&token=…` link and the QR code in the Mac's
Settings tab contain the hub token. Anyone with either can read and control your
OpenCode sessions while they are on the network. Share them only with your own
devices.

The token also grants access to `GET /api/system`, which reports host details
(OS, hardware, usernames, network addresses, installed apps and packages), and to
the read-only host file browser (`/api/files`, `/api/files/content`,
`/api/files/raw`). Treat the token as access to that inventory and to any file
your macOS user can read. The hub blocks previewing its own config and OpenCode
credential files, but other files remain readable to a paired client.

**The token also grants a shell.** The terminal API lists OpenCode's PTYs and
proxies their WebSockets (`/api/terminals`, `/api/terminals/{id}/socket`).
Anyone with the token can open a terminal in a directory of their choosing and
run anything the hub's user can run. That is the intended feature, but it makes
the token equivalent to a local login for that user. Keep it as private as a
password, rotate it by deleting `opencodebar-hub.json` and restarting the hub,
and do not expose the hub to untrusted networks.

**Terminal.app tabs are visible and writable too.** The host-terminal endpoints
(`/api/host-terminals`, `…/{tty}`, `…/{tty}/command`) read the visible text of
every Terminal.app tab and run commands in it. The mirror can contain secrets
that were printed in that tab, and a command runs with the tab's shell context.
The hub needs macOS Automation permission for Terminal.app; grant it only to a
hub you trust. Revoke it under **System Settings → Privacy & Security →
Automation**.

**The token can also see and control the screen.** When the remote helper is
enabled, `/api/remote/socket` streams the Mac's display and accepts pointer,
scroll, and keyboard events. Screen Recording and Accessibility permission must
be granted to the helper first, but once they are, any paired device can drive
the Mac. Treat pairing as full control, use `OPENCODEBAR_REMOTE=0` if you do not
want that, and revoke the helper's grants in **System Settings → Privacy &
Security** when they are no longer needed.

## Do not expose the hub directly to the internet

The hub speaks plain HTTP, not HTTPS. For access away from home, use a private
tunnel such as Tailscale, or the `make hub-tunnel` Cloudflare quick tunnel,
which terminates TLS at Cloudflare. You can also keep
`OPENCODEBAR_HUB_HOST=127.0.0.1` and forward through a tunnel that terminates
TLS.

```bash
# Hub on loopback only, exposed through a quick tunnel
OPENCODEBAR_HUB_HOST=127.0.0.1 make hub
make hub-tunnel
```

A quick tunnel is public while it runs. The random hostname is hard to guess and
every hub request still requires the Bearer token, but treat the URL like the
pairing link: stop the tunnel when you are done. Quick tunnels are intended for
personal use and have no uptime guarantee.

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

## Model providers and data training

OpenCodeBar does not upload data to an OpenCodeBar service, but the prompts and
responses still cross OpenCode to whichever model provider you configured. That
provider's logging, retention, and training terms apply, together with your
workspace privacy settings.

Some OpenCode Go models require the workspace option **Allow paid endpoints that
train on request data**. OpenCodeBar never enables that option and does not
require it: OpenCode CLI works without it, and so does the app. Do not turn it on
just to make a model work. Choose a model whose policy you accept, or set a
non-training model as OpenCode's default for the directory. The session header
and **Session settings** disclosure show the model, provider, variant, and agent
that actually ran.

See [Session detail → Models and data
training](../using/session.md#models-and-data-training) and the
[FAQ](../help/faq.md#will-opencodebar-enable-training-on-my-data).

## What OpenCodeBar does not do

- It does not delete sessions. Pause, stop, and continue only interrupt or
  restart work in an existing session.
- It does not sandbox terminal commands: they run as the hub's macOS user.
- It does not upload your data to an OpenCodeBar service.
- It does not include analytics or telemetry.
- It does not change OpenCode or Go workspace privacy settings, and it never
  enables training on request data.
- It does not bypass OpenCode's own auth; the hub authenticates to OpenCode
  using the local service credentials.

## Data removal

Deleting `~/.local/share/opencodebar/hub.sqlite` removes the hub cache. Deleting
`~/Library/Caches/OpenCodeBar/usage.json` removes the Mac's last-known usage.
Neither touches OpenCode's own data.

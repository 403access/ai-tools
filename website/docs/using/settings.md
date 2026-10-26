---
title: Settings
sidebar_position: 6
---

# Settings

The **Settings** tab is where you inspect the hub and manage the devices
connected to it.

## macOS

### Power

**Keep Mac awake** controls whether the hub blocks idle sleep while it runs.
When it is on, the hub holds a macOS idle-sleep assertion (`caffeinate -i`), so
the phone and tablet keep their connection while the Mac is otherwise idle.
The display can still turn off, and closing the lid still sleeps the Mac.

The setting is stored in the hub's `opencodebar-hub.json`, applied immediately,
and restored the next time the hub starts. It is unavailable when the hub runs
on a non-macOS host. If the hub itself is not running, nothing can keep the
Mac awake.

### Server

The Server card shows:

- hub version and address,
- uptime,
- OpenCode state (connected/offline and version),
- cached session and message counts,
- last sync time,
- the SQLite database path.

Controls:

| Action | What it does |
| --- | --- |
| **Sync now** | Requests `POST /api/sync` and refreshes cached data |
| **Restart** | Restarts the hub process (`POST /api/server/restart`) |
| **Show files** | Reveals the hub data and config files in Finder |
| **Refresh** | Re-fetches health, devices, and settings |

The Mac and iOS apps reconnect automatically after a restart.

### Devices

Every app connected to the hub appears with its name, platform, app version,
and live status. This is driven by headers each client sends:

```text
X-OpenCodeBar-Device-Id
X-OpenCodeBar-Device-Name
X-OpenCodeBar-Platform
X-OpenCodeBar-App-Version
```

The id is stable across app updates and reinstalls. If an older client
reconnects with a fresh id, the hub merges the previous row so the device is
listed once.

### Pairing

The pairing card shows a QR code and the
`opencodebar://pair?url=…&token=…` link with a copy button. In the iOS app, scan
the QR code or paste the link. Both contain the hub token, so share them only
with your own devices.

### Connection

Shows the current connection state, this device's name, and whether the hub came
from the environment override or the generated local config.

## iPhone/iPad

The iOS Settings screen includes:

- **Appearance** — follow the system or stay dark/light.
- **Status** — hub/OpenCode health, cached counts, uptime, and last sync.
- **Power** — choose whether the Mac running the hub may sleep. Turning on
  **Keep Mac awake** holds the same idle-sleep assertion as the Mac app, so the
  phone keeps its connection while the Mac is idle.
- **Hub connection** — URL, token, test, and save/reconnect.
- **Pairing link** — paste a link and apply it.
- **Remove hub configuration** — clears the URL and token from the device.

The iOS app does not expose the Mac's server restart or reveal-file controls.

## Model and data policy

Model selection lives in OpenCode, not OpenCodeBar. The apps list the models
OpenCode exposes and show which one actually ran in the session header and
**Session settings** disclosure.

OpenCodeBar never changes OpenCode or Go workspace privacy settings. In
particular, it will not enable **Allow paid endpoints that train on request
data**. New sessions use OpenCode's default model for the directory; set a
non-training default in OpenCode if you need one. See [Session detail → Models
and data training](../using/session.md#models-and-data-training).

## Security

The token is stored only on the device or in the owner-only generated file. The
Settings screen is the easiest place to copy the pairing link, but treat that
link like a password. See [Security](../hub/security.md).

---
title: Requirements
sidebar_position: 1
---

# Requirements

OpenCodeBar has three pieces: the macOS menu bar app, the iOS/iPadOS app, and
the hub that connects them. You can run any one of them, but the apps need the
hub for cached data and for phone access.

## Minimum versions

| Component | Requirement |
| --- | --- |
| macOS app | macOS 14 Sonoma or later |
| iPhone/iPad app | iOS/iPadOS 17 or later |
| Hub | [Bun](https://bun.sh) 1.1 or later |
| OpenCode | OpenCode V2, running as the background service |
| Mac build | Xcode or the Swift toolchain (`swift` on your `PATH`) |
| iOS build | Xcode with an iOS simulator, plus [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| Physical iPhone/iPad | An Apple Development signing identity, a development team, and Developer Mode enabled on the device |
| Documentation site | Node.js 20+ |

## Check the essentials

```bash
# OpenCode should report a running service and a URL.
opencode service status

# Bun runs the hub.
bun --version

# Swift builds the Mac app.
swift --version

# Xcode and XcodeGen build the iOS app.
xcodebuild -version
xcodegen --version
```

:::note
The hub is not an optional extra for the phone. The iOS app talks to the hub,
not directly to OpenCode, so the Mac running the hub must be reachable over the
LAN (or through a tunnel).
:::

## Network

- The Mac and phone should be on the same trusted network for first-time setup.
- The hub binds `0.0.0.0` by default on port `8787` so the phone can connect.
- macOS may ask for **Local Network** permission the first time an app reaches
  the hub.
- A Bearer token is always required. See [Security](../hub/security.md) before
  exposing the hub beyond your LAN.

## Optional

- **Go plan limits.** Add a console service-account key to show rolling, weekly,
  and monthly usage. See [Go plan usage](../hub/go-usage.md).
- **A physical device.** The simulator works without signing; a real device
  needs an Apple Development team.

Next: [install the hub](install-hub.md).

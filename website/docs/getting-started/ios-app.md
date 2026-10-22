---
title: Run the iPhone/iPad app
sidebar_position: 4
---

import Figure from '@site/src/components/Figure';

# Run the iPhone/iPad app

The iOS app is generated from `project.yml` with XcodeGen. Start the hub first;
the app needs it for every read and write.

## Simulator

```bash
make mobile-run
```

This generates the Xcode project, builds the app for the simulator, installs it,
launches it, and pairs it automatically when
`~/.config/opencode/opencodebar-hub.json` exists.

<Figure src="/img/screenshots/ios-live.png" alt="OpenCodeBar on iPhone" caption="The iOS app uses the same dark panel design and a floating tab dock." />

## Physical iPhone or iPad

```bash
make mobile-device
```

The script:

1. Picks the only connected device, or asks you to choose with `DEVICE=…`.
2. Uses the team selected in Xcode, falling back to the team on your Apple
   Development certificate.
3. Builds, signs, installs, and launches the app.
4. Pairs it over the Mac's LAN address, or over a running `make hub-tunnel` URL
   when one is available (needed on cellular), because `127.0.0.1` on the phone
   means the phone itself.

```bash
make mobile-device DEVICE="iPhone von Oli"
make mobile-device DEVELOPMENT_TEAM=ABCDE12345

Scripts/run-mobile-device.sh --no-build   # reinstall the last build
Scripts/run-mobile-device.sh --console    # stream app logs
```

On the first run, connect and unlock the device, tap **Trust**, and enable
**Settings → Privacy & Security → Developer Mode** on the iPhone/iPad.

:::note
A device build needs an Apple Development identity in Xcode. If provisioning
fails, sign in under **Xcode → Settings → Accounts** and try again.
:::

## Use it on cellular or another network

A direct LAN address only works while the phone and the Mac are on the same
Wi-Fi. On cellular, start a tunnel in a second terminal and keep it running:

```bash
# terminal 1: the hub
make hub

# terminal 2: a public HTTPS URL for the phone
make hub-tunnel

# terminal 3: build, install, and pair over the tunnel
make mobile-device
```

`make hub-tunnel` uses a Cloudflare quick tunnel, so no account is needed. It
prints the URL and a pairing link, and writes
`~/.config/opencode/opencodebar-hub-tunnel.json`; `make mobile-device` and the
Mac app's pairing QR code use that URL automatically. The URL is public while
the process runs, but every request still requires the hub token.

:::note
USB tethering is not enough on its own. iOS does not route from an app back to
the tethered Mac (`192.0.0.2`), even though the Mac can reach the internet
through the phone. Use the tunnel in that case too.
:::

For a stable address, run [Tailscale](https://tailscale.com) on the Mac and the
phone and pair with the Mac's `100.x.y.z` address instead; no public URL is
created.

## Build only

```bash
make mobile-project   # regenerate OpenCodeBarMobile.xcodeproj
make mobile-build     # build for the simulator
```

You can also open `OpenCodeBarMobile.xcodeproj` in Xcode after
`make mobile-project` and run the `OpenCodeBarMobile` scheme.

## Configure the hub

The app pairs with:

- the QR code in the Mac app's **Settings → Pairing**,
- the `opencodebar://pair?url=…&token=…` link printed by the hub,
- a pasted hub URL and token in **Settings**, or
- automatic pairing from `make mobile-run` / `make mobile-device`.

While `make hub-tunnel` is running, the Mac app's QR code and the automatic
pairing use the tunnel URL instead of the LAN address.

The token is stored on the device. It is not synced to iCloud by OpenCodeBar.

## App permissions

- **Local Network** — required to reach the hub on your Mac.
- **Camera** — only when you scan a pairing QR code.
- **Microphone** — only when you tap the dictation button.
- **Speech Recognition** — to turn speech into an editable prompt.

Speech recognition runs on the device when the current language supports it;
otherwise the system service may process the audio. See [Voice input](../using/voice.md).

Next: [pair the apps](pairing.md).

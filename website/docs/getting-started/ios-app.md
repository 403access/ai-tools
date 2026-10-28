---
title: Run the iPhone/iPad app
sidebar_position: 4
---

import Figure from '@site/src/components/Figure';

# Run the iPhone/iPad app

The iOS app is generated from `project.yml` with XcodeGen. Start the hub first;
the app needs it for every read and write.

:::note
New sessions use OpenCode's default model for the directory. OpenCodeBar never
enables **Allow paid endpoints that train on request data**, and you do not need
to enable it to use the phone. If your default is a training model, set a
non-training default in OpenCode, or use **Retry options…** after a failed
turn. See [Session detail → Models and data
training](../using/session.md#models-and-data-training).
:::

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

## Several versions side by side

Reviewing branches does not require reinstalling one build over another. Every
git worktree can be installed as its own app with a distinct bundle id and
home-screen name, all paired with the same hub:

```bash
make hub                # terminal 1
make mobile-variants    # terminal 2: one app per worktree
```

The normal app stays installed, and `make mobile-device` keeps using
`dev.opencodebar.mobile`. Pass worktree paths or branches in `ARGS` to build a
subset, and use `Scripts/run-mobile-variants.sh --list` to preview names and
bundle ids. See [Review builds side by side](../development/variant-builds.md)
for naming, signing, clean-up, and what the variants share.

## Remote desktop permissions

`make hub` also builds the ScreenCaptureKit helper used by **Host → Remote**. The
first time you open Remote, allow **Screen Recording** and **Accessibility** for
the helper on the Mac. Screen Recording is required for the image; Accessibility
is required to send taps and keys. See [Remote desktop](../using/remote.md) for
the full setup and troubleshooting guide.

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
the tethered Mac at its `192.0.0.x` address, even though the Mac can reach the
internet through the phone. Use Wi-Fi, Tailscale, or the tunnel in that case.
:::

If the hub restarts on a different address or port, the phone still has the old
URL saved. Re-pair from the Mac app's QR code or pairing link, or rerun
`make mobile-device` while `make hub-tunnel` is running. `make mobile-device`
will not auto-pair to a USB-tether address because the phone cannot reach it.

For a stable address, run [Tailscale](https://tailscale.com) on the Mac and the
phone and pair with the Mac's `100.x.y.z` address instead; no public URL is
created.

## Install without a cable (over the air)

`make mobile-device` needs the phone and the Mac to talk over USB or the same
network. An over-the-air build removes both: the hub hosts the IPA, and the
phone downloads it from a normal HTTPS link.

```bash
# terminal 1: the hub
make hub

# terminal 2: a public HTTPS URL (only needed off the LAN)
make hub-tunnel

# terminal 3: archive, export, and publish
make mobile-ota
```

The script archives the app, exports a **development-signed IPA**, copies it
into the hub's data directory, and prints an install page URL plus a QR code.
Open the link or scan the QR on the phone and tap **Install**; iOS shows its own
confirmation. The page also has a **Pair this hub** button, so a fresh install
connects with one tap instead of typing a URL and token.

You can also do this without a terminal: the Mac app's
**Settings → Deployments** has a **Build & install** button. The hub runs the
same archive/export in the background, shows the output while it works, and
then shows the install QR and link. When the phone app is connected, publishing
a build also sends it an **Update available** banner that opens the install.

:::note
iOS only installs an app when the device asks for it. A hub cannot push an
install to a phone without an MDM server, so the last tap always happens on the
phone.
:::

Requirements and caveats:

- An HTTPS URL is mandatory. `itms-services` links are rejected over plain HTTP,
  which is why `make hub-tunnel` (or Tailscale with HTTPS) is needed off the
  LAN.
- The IPA is signed with the development profile, so the phone's UDID must be in
  that profile. Usually it already is after the first `make mobile-device`, which
  registers the device. Ad-hoc export needs a paid team and a manually managed
  profile; OpenCodeBar deliberately uses the development profile instead.
- The developer certificate must be trusted on the phone: **Settings → General →
  VPN & Device Management**. It is after the first Xcode/USB install.
- Builds are pruned to the newest five; change that with
  `OPENCODEBAR_OTA_KEEP`.

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

## Offline cache

The iOS app keeps a local SQLite cache in
`Library/Application Support/OpenCodeBar/opencodebar.sqlite`. Sessions,
projects, stats, usage, and the newest messages of opened sessions are written
there, so a cold launch renders the last snapshot before the first request
finishes. The app then asks the hub for changes since its last revision with
`GET /api/sync?since=…`; a quiet hub returns empty arrays, and only sessions
that actually moved are transferred. Pairing a different hub clears the cache.

Deleting the app removes the cache. There is no cache control in Settings yet.

## Home Screen widgets

The Xcode project also builds **OpenCodeBarWidgets**, containing two widgets:

- **Live Sessions** — running-session count, what each session is doing right
  now, elapsed time, project, cost, and tokens. Medium shows two running rows;
  large adds more running sessions and recent sessions.
- **Usage** — today's steps, cost, tokens, streak, prompts, tool calls, a
  14-day activity chart, and the Go plan-limit bars with reset countdowns.

Both support small, medium, and large sizes. Long-press the Home Screen, tap
**Edit → Add Widget**, search for **OpenCodeBar**, and pick a size. Tapping a
widget opens the matching tab.

The extension talks to the same hub directly and caches its last successful
fetch, so widgets still render usable state while the app is closed or the Mac
is unreachable. The app and extension share pairing details through a keychain
access group, which the team's provisioning profile already authorizes. Widget
refresh is scheduled by iOS, typically every five to fifteen minutes, and the
app nudges WidgetKit when its data changes in the foreground.

:::note
`make mobile-run` builds the simulator app without code signing, so the shared
keychain group is not applied there and the widget shows **Pair your hub**. Use
a signed simulator run from Xcode (with a development team) or
`make mobile-device` to test widgets with live data.
:::

## App permissions

- **Local Network** — required to reach the hub on your Mac, including from the
  Home Screen widgets.
- **Camera** — only when you scan a pairing QR code.
- **Microphone** — only when you tap the dictation button.
- **Speech Recognition** — to turn speech into an editable prompt.

Speech recognition runs on the device when the current language supports it;
otherwise the system service may process the audio. See [Voice input](../using/voice.md).

Next: [pair the apps](pairing.md).

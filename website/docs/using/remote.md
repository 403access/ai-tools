---
title: Remote desktop
sidebar_position: 6
---

# Remote desktop

The iPhone/iPad app can stream and control the Mac that runs the hub. Open the
**Host** tab and switch the segmented control from **System** to **Remote**.

Remote desktop is currently an iOS feature. The shared models and `HubAPI`
methods are ready for a Mac client, but the Mac panel does not show the screen
yet.

## How it works

A small ScreenCaptureKit helper, `OpenCodeBarRemoteHost`, captures one display
and sends JPEG frames to the hub. The hub relays them over the same authenticated
WebSocket that carries input back, so the phone only needs the hub URL and
token. The helper starts when the first viewer connects and stops capturing
eight seconds after the last viewer leaves.

`make hub` builds the helper automatically. To build or rebuild it alone:

```sh
make remote-host
```

The hub looks for `.build/debug/OpenCodeBarRemoteHost`, then the release and
`dist/` variants. Set `OPENCODEBAR_REMOTE_HOST=/path/to/helper` to use another
path, or start the hub with `OPENCODEBAR_REMOTE=0` to disable remote desktop.

## Permissions

Two macOS privacy grants are involved. The phone shows a card with an **Allow**
button; the actual dialog appears on the Mac.

| Permission | Needed for | Without it |
| --- | --- | --- |
| Screen Recording | Capturing the display | The Remote screen stays black and explains what is missing |
| Accessibility | Posting pointer and keyboard events | The stream is **View only** |

If the prompt does not appear, open **System Settings → Privacy & Security**,
add the helper under the matching pane, and restart the hub. During development
the helper lives inside `.build/`, so macOS may attribute the grant to the
terminal (or Bun) that launched the hub; a distributed build should ship it in a
signed app bundle so the grants belong to OpenCodeBar.

Screen Recording may require the helper to be restarted after the toggle is
flipped. The helper retries every three seconds while it waits, so granting the
permission and returning to the app is usually enough.

## Gestures

| Gesture | Action |
| --- | --- |
| Tap | Left click (or right click when **Right** is enabled) |
| Double tap | Double click |
| One-finger drag | Drag |
| Pinch | Zoom the canvas (1×–4×) |
| Two-finger tap | Toggle fit / zoomed |
| Two-finger pan | Pan the zoomed canvas, or scroll the Mac at fit |

The screen opens slightly zoomed so text is readable on a phone; tap **Zoom** or
two-finger tap to see the whole display.

## Controls

The control strip has:

- **Zoom** — toggle fit and zoomed.
- **Keyboard** — show the software keyboard. Hardware keyboards connected to the
  phone also work while the field is focused.
- Modifier chips for **⌘**, **⌃**, **⌥**, and **⇧**. They apply to the next key
  or typed text and then clear.
- **esc**, **tab**, **⌫**, **↩**, and the four arrow keys.
- **Right click** — makes the next taps use the secondary mouse button.
- **Quality** — **Sharp** (1920 px, 18 fps), **Balanced** (1600 px, 12 fps), or
  **Fast** (1280 px, 8 fps). Use Fast on a cellular tunnel.

The status strip shows the connection state, the remote display size, the
measured frame rate, and **View only** when Accessibility is missing.

## Security and bandwidth

Every frame and input message uses the hub's Bearer token. On a LAN the traffic
is HTTP/WebSocket, like the rest of the hub; use a Cloudflare tunnel or Tailscale
when the phone is off the local network. There is no TLS termination inside the
hub itself.

JPEG frames are roughly 1–2 MB/s at Balanced for a full-screen change. The phone
asks the hub to lower resolution and frame rate through the Quality menu. Any
device paired with the hub can control the Mac while a viewer is connected;
input is last-writer-wins if two phones are open at once.

## Troubleshooting

- **Remote host not available** — the helper binary is missing. Run
  `make remote-host` (or `make hub`, which builds it) and restart the hub.
- **Black screen / Allow Screen Recording** — flip the Screen Recording switch
  for the helper, then return to the app.
- **View only** — flip Accessibility for the helper. The screen keeps updating,
  but taps and keys are ignored until then.
- **Frozen image** — capture stopped (usually because the Mac slept or the
  helper lost its connection). Tap the play/stop button or use **Reconnect** in
  the **⋯** menu. Keeping **Keep Mac awake** enabled in Settings avoids idle
  sleep.
- **Tunnel is slow** — choose **Fast** quality. A Cloudflare quick tunnel adds
  latency and may compress less efficiently than the LAN.

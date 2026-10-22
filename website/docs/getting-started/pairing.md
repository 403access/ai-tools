---
title: Pair the apps
sidebar_position: 5
---

# Pair the apps

The hub is the only thing the apps talk to. Both need its URL and a Bearer
token.

## macOS

The Mac app connects with no configuration: the hub writes its URL and token to
`~/.config/opencode/opencodebar-hub.json` (owner-only), and the app reads that
file on launch.

If the hub runs on another machine, or you want to override the file, use the
environment or the optional config file.

## iPhone/iPad

Open **Settings** in the app and either:

1. Scan the QR code shown in the Mac app's **Settings → Pairing**,
2. Paste the hub URL and token, then tap **Test connection** and
   **Save & Connect**, or
3. Paste the `opencodebar://pair?url=…&token=…` link the hub prints and tap
   **Apply pairing link**.

The QR scanner uses the camera and only accepts `opencodebar://` pairing
payloads.

`make mobile-run` and `make mobile-device` apply the pairing automatically when
the generated hub config exists.

## Override order

Clients resolve the hub connection in this order:

1. `$OPENCODEBAR_HUB_URL` / `$OPENCODEBAR_HUB_TOKEN`
2. `hubURL` / `hubToken` in `~/.config/opencode/opencodebar.json`
3. the generated `~/.config/opencode/opencodebar-hub.json`

For the phone, the values saved in the app's Settings take precedence over the
generated file bundled during a build.

## Pairing link

The link contains the hub token. Share it only with your own devices:

```text
opencodebar://pair?url=http%3A%2F%2F192.168.1.20%3A8787&token=<token>
```

The iOS app registers the `opencodebar://` URL scheme. Tapping a link opens the
app and applies the pairing values.

## Add another phone

Open **Settings** on the Mac, then scan the QR code or copy the pairing link.
The QR code uses the Mac's LAN address so the phone can reach it. The phone
appears in the Mac's **Devices** list after its first authenticated request.
Each installation gets a stable device id, name, platform, and app version.

## If pairing fails

- Use the Mac's LAN address, not `127.0.0.1`, on a physical phone.
- Put both devices on the same Wi-Fi network.
- Allow Local Network access for OpenCodeBar in
  **System Settings → Privacy & Security → Local Network**.
- Check that the hub is still running and the port did not change.
- Verify `curl http://<mac-lan-ip>:8787/api/ping` from another device.

More in [Troubleshooting](../help/troubleshooting.md).

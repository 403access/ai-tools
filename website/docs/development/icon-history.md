---
title: Icon history
sidebar_position: 7
---

import Figure from '@site/src/components/Figure';

# Icon history

The app icon follows the menu bar's `terminal` SF Symbol: a prompt chevron and
cursor block on a dark screen. Every generation is kept in
`website/static/img/icon-history/` so the mark's evolution stays reviewable even
as the live icon files change.

## At a glance

<div className="screenshotGrid">
  <Figure src="/img/icon-history/macos-v1-original.png" alt="Original OpenCodeBar icon: a teal-green squircle with a dark angle-bracket-slash mark" caption="v1 — original </> mark" />
  <Figure src="/img/icon-history/macos-v2-terminal.png" alt="Second OpenCodeBar icon: a floating dark terminal window with a green prompt and cursor" caption="v2 — floating terminal" />
  <Figure src="/img/icon-history/macos-v3-fill.png" alt="Current OpenCodeBar icon: the terminal window fills the whole icon with a green prompt and cursor" caption="v3 — terminal fills the canvas (current)" />
  <Figure src="/img/icon-history/website-icon-v3.png" alt="Website icon matching the terminal-filling app icon" caption="Website — now using v3" />
</div>

| Generation | Introduced | Mark | Where it lives |
| --- | --- | --- | --- |
| v1 | 2026-10-19 | Flat teal `</>` on a green gradient | Replaced; kept here |
| v2 | 2026-10-23 | Dark terminal window floating over a charcoal squircle | Previous default; `--floating` |
| v3 | 2026-10-23 | The terminal window itself fills the icon | **Current default** for macOS, iOS and the website |
| Website (v1) | 2026-10-19 | Teal `</>` (the v1 mark) | Replaced 2026-10-23; kept here |

## v1 — Original code mark

The first icon was a bright green gradient squircle with a dark `</>` rendered in
the system monospaced font. It matched the original website logo and was used
for both apps.

<div className="screenshotGrid">
  <Figure src="/img/icon-history/macos-v1-original.png" alt="v1 macOS app icon with a dark angle-bracket-slash glyph on a green gradient" caption="v1 macOS — 1024 px" />
  <Figure src="/img/icon-history/website-icon-512.png" alt="Old website icon with a dark angle-bracket-slash glyph on a teal gradient" caption="Old website icon — v1 mark" />
</div>

The website used a vector rendition of the same mark (`</>` on a teal gradient)
for its logo, favicon and Apple touch icon. Those files have been replaced, but
copies from 2026-10-23 are kept in this folder as `website-icon.svg` and
`website-icon-512.png`.

## v2 — Floating terminal

The redesign moved to the dark theme palette and made the tray icon the subject:
a charcoal squircle with an accent bloom, a floating terminal window, traffic
lights in the status colours, and a glowing `>` prompt with a cursor.

<div className="screenshotGrid">
  <Figure src="/img/icon-history/macos-v2-terminal.png" alt="v2 macOS app icon with a floating terminal window" caption="macOS — previous default" />
  <Figure src="/img/icon-history/ios-v2-terminal.png" alt="v2 iOS app icon, full-bleed terminal window" caption="iOS — previous default, full-bleed" />
</div>

The iOS variant is full-bleed: it fills the square so iOS can apply its own
rounded mask. The same generator renders both, with `--full-bleed` selecting the
iOS composition. v2 remains available with `--floating`.

## v3 — Terminal fills the canvas

The current version removes the backdrop padding: the terminal window *is* the
icon, keeping only the standard macOS edge inset. The screen, title bar, dots and
prompt scale up to fill the available space.

<div className="screenshotGrid">
  <Figure src="/img/icon-history/macos-v3-fill.png" alt="v3 macOS app icon where the terminal window fills the canvas" caption="macOS — default" />
  <Figure src="/img/icon-history/ios-v3-fill.png" alt="v3 iOS app icon where the terminal window fills the canvas" caption="iOS — default, full-bleed" />
  <Figure src="/img/icon-history/website-icon-v3.png" alt="Website icon using the v3 terminal artwork" caption="Website — logo, favicon and touch icons" />
</div>

v3 is used by the macOS app, the iOS app and both websites. On the web it is
served as PNG renders generated from the same script: `logo.png` (navbars) and
`favicon.png`, plus `icon-192.png` / `icon-512.png` for Apple touch and share
icons.

## Small sizes

The generator adapts the artwork below 128 px: the full window is used at
128 px and above, the traffic lights disappear at 64 px, and 16–32 px render
just the bold prompt glyph so it stays legible in the Dock and Finder.

## Regenerating

```bash
make icon          # macOS → Assets/AppIcon.icns
make icon-classic  # previous floating terminal → Assets/AppIconClassic.icns
make mobile-icon   # iOS → Mobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
make web-icons     # website logo, favicon and touch icons
```

`--full-bleed` selects the iOS composition, and `--floating` restores the v2
artwork:

```bash
swift Scripts/make-icon.swift --full-bleed .build/ios-icon.iconset
swift Scripts/make-icon.swift --floating --full-bleed .build/ios-classic.iconset
```

The macOS `.icns` files are generated and git-ignored. The iOS app icon, the
website icons and the history renders in this folder are committed so the
document stays stable.

## Live assets

| Asset | Path |
| --- | --- |
| macOS default icon | `Assets/AppIcon.icns` (generated) |
| macOS previous icon | `Assets/AppIconClassic.icns` (generated) |
| iOS icon | `Mobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |
| Marketing site icon | `docs/assets/logo.png`, `docs/assets/icon-192.png`, `docs/assets/icon-512.png` |
| Docs site icon | `website/static/img/logo.png`, `website/static/img/favicon.png` |

## History files

| File | Source |
| --- | --- |
| `macos-v1-original.png` | `Scripts/make-icon.swift` at commit `04e7d41^` |
| `macos-v2-terminal.png` | `swift Scripts/make-icon.swift --floating` |
| `ios-v2-terminal.png` | `swift Scripts/make-icon.swift --floating --full-bleed` |
| `macos-v3-fill.png` | `swift Scripts/make-icon.swift` |
| `ios-v3-fill.png` | `swift Scripts/make-icon.swift --full-bleed` |
| `website-icon-v3.png` | `make web-icons` |
| `website-icon.svg` | Old website icon, v1 snapshot |
| `website-icon-512.png` | Old website icon, v1 snapshot |

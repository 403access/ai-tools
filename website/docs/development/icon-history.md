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
  <Figure src="/img/icon-history/macos-v2-terminal.png" alt="Second OpenCodeBar icon: a floating dark terminal window with a green prompt and cursor" caption="v2 — floating terminal (default)" />
  <Figure src="/img/icon-history/macos-v3-fill.png" alt="Third OpenCodeBar icon: the terminal window fills the whole icon with a green prompt and cursor" caption="v3 — terminal fills the canvas (alternate)" />
</div>

| Generation | Introduced | Mark | Where it lives |
| --- | --- | --- | --- |
| v1 | 2026-10-19 | Flat teal `</>` on a green gradient | Replaced; kept here |
| v2 | 2026-10-23 | Dark terminal window floating over a charcoal squircle | Default macOS + iOS icon |
| v3 | 2026-10-23 | The terminal window itself fills the icon | Alternate macOS + iOS icon |
| Website | 2026-10-19 | Teal `</>` (the v1 mark) | `docs/assets/logo.svg` and `website/static/img/logo.svg` |

## v1 — Original code mark

The first icon was a bright green gradient squircle with a dark `</>` rendered in
the system monospaced font. It matched the original website logo and was used
for both apps.

<div className="screenshotGrid">
  <Figure src="/img/icon-history/macos-v1-original.png" alt="v1 macOS app icon with a dark angle-bracket-slash glyph on a green gradient" caption="v1 macOS — 1024 px" />
  <Figure src="/img/icon-history/website-icon-512.png" alt="Website icon with a dark angle-bracket-slash glyph on a teal gradient" caption="Website icon — still on the v1 mark" />
</div>

The website kept this mark as an SVG (`logo.svg`), which also produces the
favicon and Apple touch icon. The copies in this history are snapshots from
2026-10-23:

- `docs/assets/logo.svg` — marketing site, favicon, and touch icon source
- `website/static/img/logo.svg` — Docusaurus navbar logo
- `website/static/img/favicon.svg` — Docusaurus favicon

## v2 — Floating terminal

The redesign moved to the dark theme palette and made the tray icon the subject:
a charcoal squircle with an accent bloom, a floating terminal window, traffic
lights in the status colours, and a glowing `>` prompt with a cursor.

<div className="screenshotGrid">
  <Figure src="/img/icon-history/macos-v2-terminal.png" alt="v2 macOS app icon with a floating terminal window" caption="macOS — default icon" />
  <Figure src="/img/icon-history/ios-v2-terminal.png" alt="v2 iOS app icon, full-bleed terminal window" caption="iOS — full-bleed, masked by iOS" />
</div>

The iOS variant is full-bleed: it fills the square so iOS can apply its own
rounded mask. The same generator renders both, with `--full-bleed` selecting the
iOS composition.

## v3 — Terminal fills the canvas

The alternate version removes the backdrop padding: the terminal window *is* the
icon, keeping only the standard macOS edge inset. The screen, title bar, dots and
prompt scale up to fill the available space.

<div className="screenshotGrid">
  <Figure src="/img/icon-history/macos-v3-fill.png" alt="v3 macOS app icon where the terminal window fills the canvas" caption="macOS — --fill" />
  <Figure src="/img/icon-history/ios-v3-fill.png" alt="v3 iOS app icon where the terminal window fills the canvas" caption="iOS — --fill --full-bleed" />
</div>

v3 is available as an alternate; v2 remains the default app icon.

## Small sizes

The generator adapts the artwork below 128 px: the full window is used at
128 px and above, the traffic lights disappear at 64 px, and 16–32 px render
just the bold prompt glyph so it stays legible in the Dock and Finder.

## Regenerating

```bash
make icon          # macOS default → Assets/AppIcon.icns
make icon-fill     # macOS alternate → Assets/AppIconFill.icns
make mobile-icon   # iOS default → Mobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

The iOS alternate is generated directly:

```bash
mkdir -p .build/ios-icon-fill
swift Scripts/make-icon.swift --fill --full-bleed .build/ios-icon-fill
cp .build/ios-icon-fill/icon_512x512@2x.png Mobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

The macOS `.icns` files are generated and git-ignored. The iOS app icon is
committed, and the history renders in this folder are committed so the document
stays stable.

## Live assets

| Asset | Path |
| --- | --- |
| macOS default icon | `Assets/AppIcon.icns` (generated) |
| macOS alternate icon | `Assets/AppIconFill.icns` (generated) |
| iOS icon | `Mobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |
| Marketing site icon | `docs/assets/logo.svg`, `docs/assets/icon-192.png`, `docs/assets/icon-512.png` |
| Docs site icon | `website/static/img/logo.svg`, `website/static/img/favicon.svg` |

## History files

| File | Source |
| --- | --- |
| `macos-v1-original.png` | `Scripts/make-icon.swift` at commit `04e7d41^` |
| `macos-v2-terminal.png` | `swift Scripts/make-icon.swift` |
| `ios-v2-terminal.png` | `swift Scripts/make-icon.swift --full-bleed` |
| `macos-v3-fill.png` | `swift Scripts/make-icon.swift --fill` |
| `ios-v3-fill.png` | `swift Scripts/make-icon.swift --fill --full-bleed` |
| `website-icon.svg` | Copy of `docs/assets/logo.svg` |
| `website-icon-512.png` | Copy of `docs/assets/icon-512.png` |

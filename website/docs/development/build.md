---
title: Build from source
sidebar_position: 1
---

# Build from source

The repository contains the macOS Swift package, the iOS XcodeGen project, the
Bun hub, and this Docusaurus site.

## Prerequisites

- macOS 14+ with Xcode or the Swift toolchain.
- Bun 1.1+.
- XcodeGen for the iOS app.
- Node.js 20+ for this documentation site.

See [Requirements](../getting-started/requirements.md) for the full list.

## macOS app

```bash
swift build                 # debug build
swift test                  # unit tests
Scripts/build-app.sh        # assemble dist/OpenCodeBar.app
```

Or through Make:

```bash
make build
make test
make app
make run
```

The app bundle is assembled in `dist/`. The first build also generates the icon
and ad-hoc signs the bundle.

## iOS app

```bash
make mobile-project   # xcodegen generate
make mobile-build     # simulator build
make mobile-run       # build, install, launch, and pair
make mobile-device    # build, sign, install, launch on a device
```

See [Run the iPhone/iPad app](../getting-started/ios-app.md).

## Hub

```bash
cd server
bun install
bun run start
```

Or:

```bash
make hub
make hub-dev
make hub-test
```

## Documentation site

```bash
make docs         # local dev server with hot reload
make docs-build   # production build into website/build
make docs-serve   # serve the production build
```

The production site is assembled for `/ai-tools/docs/`; see
[Documentation site](docs-site.md).

## Clean

```bash
make clean
```

This removes Swift build products, `dist/`, hub dependencies, the generated
Xcode project, and the docs build.

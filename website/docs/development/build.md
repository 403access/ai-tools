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
and ad-hoc signs the bundle. SwiftPM fetches
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), the terminal emulator
used by the System tab, on the first build.

The hub reads Terminal.app tabs through macOS automation. The first time the
Terminal.app section or its command field is used, macOS asks for permission to
control Terminal.app. Approve it for the process running the hub (usually the
terminal that ran `make hub`), or enable it later under **System Settings →
Privacy & Security → Automation**.

## iOS app

```bash
make mobile-project   # xcodegen generate
make mobile-build     # simulator build (app + widget extension)
make mobile-run       # build, install, launch, and pair
make mobile-device    # build, sign, install, launch on a device
make mobile-variants  # one installable variant per git worktree
```

Xcode resolves SwiftTerm from the package reference in `project.yml` on the
first build. The generated project has two targets: `OpenCodeBarMobile` and the
`OpenCodeBarWidgets` extension. The app and extension share the hub connection
through a keychain access group, so widgets work as soon as the app is paired;
no extra capability setup is needed beyond normal automatic signing.

See [Run the iPhone/iPad app](../getting-started/ios-app.md). To install several
worktree builds on one phone at once, see [Review builds side by
side](variant-builds.md).

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

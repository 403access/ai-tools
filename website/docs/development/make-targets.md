---
title: Make targets
sidebar_position: 2
---

# Make targets

| Target | What it does |
| --- | --- |
| `make build` | Compile the Swift package in debug |
| `make test` | Run Swift unit tests |
| `make app` | Assemble `dist/OpenCodeBar.app` in release |
| `make run` | Build and launch the Mac app |
| `make restart` | Rebuild and restart the running Mac app |
| `make preview` | Open the panel in a normal window |
| `make shots` | Regenerate docs screenshots |
| `make site` | Open the marketing site (`docs/index.html`) |
| `make icon` | Regenerate the Mac app icon |
| `make hub` | Install and run the SQLite hub |
| `make hub-dev` | Hub with auto-reload |
| `make hub-test` | Bun hub tests |
| `make mobile-project` | Generate the iOS Xcode project |
| `make mobile-build` | Build the iOS app for the simulator |
| `make mobile-run` | Build, install, launch, and pair the simulator app |
| `make mobile-device` | Build, sign, install, launch, and pair a device |
| `make mobile-icon` | Regenerate the iOS app icon |
| `make docs` | Run the Docusaurus docs dev server |
| `make docs-build` | Build the docs for production |
| `make docs-serve` | Serve the built docs locally |
| `make clean` | Remove build products and generated files |

## Common combinations

```bash
# Hub in one terminal, Mac app in another
make hub
make run

# Phone on the simulator
make mobile-run

# Phone on a real device
make mobile-device DEVICE="iPhone von Oli"

# Docs while editing markdown
make docs
```

## `make restart`

`Scripts/restart.sh` builds before stopping the old process, so a failed build
does not leave you without a running app.

```bash
Scripts/restart.sh --no-build
CONFIG=debug Scripts/restart.sh
```

## `make mobile-device`

```bash
make mobile-device
make mobile-device DEVICE="My iPad"
make mobile-device DEVELOPMENT_TEAM=ABCDE12345
```

The script uses the team selected in Xcode, falling back to the team on your
Apple Development certificate. It pairs over the Mac's LAN address. See
[iOS app](../getting-started/ios-app.md).

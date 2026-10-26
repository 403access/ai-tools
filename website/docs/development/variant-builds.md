---
title: Review builds side by side
sidebar_position: 3
---

# Review builds side by side

Several versions of the iOS app can be installed on one iPhone or iPad at the
same time, one per git worktree. Each copy keeps its own icon name, container,
and cache, so reviewing a branch never replaces the build on someone else's
phone.

```bash
make hub                     # terminal 1
make mobile-variants         # terminal 2: every worktree
```

Every worktree from `git worktree list` is built, signed, installed, launched,
and paired. The checkout you run the command from is included, with any
uncommitted changes. Pass worktree paths or branch names to build only some of
them, and use `--list` / `--dry-run` to check the selection first:

```bash
Scripts/run-mobile-variants.sh --list
Scripts/run-mobile-variants.sh main feature/virtual-machines
Scripts/run-mobile-variants.sh "Kanban=../worktrees/kanban"
Scripts/run-mobile-variants.sh --dry-run --prefix "Review "
make mobile-variants ARGS="--device 'iPhone von Oli' --no-build"
```

`--no-build` reinstalls the last build of each variant, which is handy after a
phone restart. `--device` behaves like `make mobile-device DEVICE=…`. The
wrapper forwards `DEVELOPMENT_TEAM`, `OPENCODEBAR_HUB_URL`,
`OPENCODEBAR_HUB_TOKEN`, `HUB_LAN_IP`, and `OPENCODEBAR_TUNNEL_CONFIG` to
`Scripts/run-mobile-device.sh`.

## What each variant gets

| Setting | Normal app | Variant |
| --- | --- | --- |
| App bundle id | `dev.opencodebar.mobile` | `dev.opencodebar.mobile.<slug>` |
| Widget bundle id | `dev.opencodebar.mobile.widgets` | `dev.opencodebar.mobile.<slug>.widgets` |
| Home-screen name | `OpenCodeBar` | `OCB <label>` (24 characters max) |
| DerivedData | `.build/ios-device` | `.build/ios-device-<slug>` |
| Container, caches, database | its own | its own |

The label comes from the branch name, or the directory name for a detached
worktree. It is lowercased and slugified for the bundle id; labels that collide
get `-2`, `-3`, and so on. Use `Label=path` to choose the name yourself.

iOS identifies installed apps by bundle id, so the suffix is what allows several
copies to coexist. The app and its widget extension must stay in the same
prefix. Both come from `VARIANT_SUFFIX` in `project.yml`, which
`Scripts/run-mobile-variants.sh` sets on the `xcodebuild` command line. The
generated Info.plist takes its display name from `VARIANT_NAME`.

## What the variants share

- **Hub pairing.** All variants use the same keychain access group and keychain
  service, so pairing one pairs all of them. `DeviceIdentity` prefers the shared
  device id, so the hub lists the phone once and shows the app version of
  whichever variant last synced.
- **The `opencodebar://` URL scheme.** Every variant registers it. Widget taps
  and pairing links therefore open an unspecified copy when more than one is
  installed. Launching through the script's `--payload-url` still pairs the
  exact variant. If deep links must be deterministic, uninstall the other
  variants or add a per-variant scheme.
- **Signing team and capabilities.** Variants differ only in bundle id; the
  keychain group and automatic signing setup are unchanged.

## Signing and App IDs

Each new variant registers one App ID with Apple (plus the widget's nested id)
through automatic signing, so the first build of a variant needs network access
and may take a little longer. If provisioning fails, sign in under **Xcode →
Settings → Accounts** and run the command again.

A free Apple ID works, but has weekly App ID limits and expires profiles after
seven days, so a paid team is less surprising when many branches are in review.
Pairing a variant needs the device to be registered, which the device script
already requests with `-allowProvisioningDeviceRegistration`.

If Xcode reports that the provisioning profile does not include
`keychain-access-groups`, open **Xcode → Settings → Accounts → Manage
Certificates** and let automatic signing repair the profile, or register the new
bundle id in the developer portal with **Keychain Sharing** enabled.

## Worktrees that predate variant support

`project.yml` needs the `$(VARIANT_SUFFIX)` and `$(VARIANT_NAME)` placeholders
shown above. The wrapper checks each worktree and, when they are missing,
patches the file for the duration of that build and restores it afterwards, so
the worktree stays clean. If a branch later adds its own `project.yml` changes,
cherry-pick the variant-support commit from `main` instead of relying on the
temporary patch.

## Removing variants

Uninstall each bundle id from the phone, for example:

```bash
xcrun devicectl list devices
xcrun devicectl device uninstall app --device <id> dev.opencodebar.mobile.kanban
```

Removing a worktree also removes its build output:

```bash
git worktree remove ../worktrees/kanban
rm -rf .build/ios-device-kanban   # run inside the worktree before removing it
```

The normal app is untouched by any of this; `make mobile-device` keeps using
`dev.opencodebar.mobile`.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| The new build replaced an installed app | Both used the same bundle id. Run through `Scripts/run-mobile-variants.sh` (or pass `--variant`) instead of `make mobile-device`. |
| The variant does not show up after install | The home-screen name may be truncated to `OCB …`; check the last screen or the App Library. Widgets appear under that name in the widget gallery too. |
| Pairing was not applied | Variants share the keychain, so if one is paired all are. Otherwise pair from **Settings** in that variant, or run again with a reachable hub URL (or `make hub-tunnel`). |
| Widget or link opens the wrong variant | All variants register `opencodebar://`; iOS picks one. Open the intended app directly. |
| An old worktree fails to generate the project | Its `project.yml` was customized so the temporary patch did not apply. Cherry-pick the variant-support commit from `main`. |
| The phone shows the old version | `--no-build` installs the last build; drop it to rebuild, or check that the variant slug matches the one you are looking for. |

---
title: Virtual machines
sidebar_position: 6
---

# Virtual machines

The **VMs** tab builds and runs declarative NixOS guests on the Mac that runs
the hub. It uses Apple's Virtualization.framework, so the guest is a native
arm64 machine rather than an emulated one. The same tab is available on macOS
and iOS/iPadOS.

## What it manages

- A **definition** (`vm.json`), a generated `configuration.nix`, and a flake.
- A **raw EFI disk image** built by Nix and copied out of the Nix store.
- A **per-VM SSH key** and an `opencodebar` user with passwordless `sudo`.
- A **serial log**, build log, apply log, and live metrics.
- A detached **`OpenCodeBarVZ` helper** process per running guest. The helper
  owns Virtualization.framework and survives a hub restart; the hub re-adopts it
  from `runtime.json`.

Everything lives under `~/.local/share/opencodebar/vms/` (override with
`OPENCODEBAR_VM_DIR`). The directory is owner-only.

## Setup

Virtual machines need an Apple silicon Mac running macOS 14 or later, plus:

1. **Nix** — install it from [nixos.org/download](https://nixos.org/download). The hub finds Nix on
   `PATH` or in the usual profile locations. Set `OPENCODEBAR_NIX` to point at a
   specific binary.
2. **An `aarch64-linux` builder** — a NixOS image is Linux, even when the host is
   macOS. The easiest local builder is:

   ```sh
   nix --extra-experimental-features 'nix-command flakes' run nixpkgs#darwin.linux-builder
   ```

   It starts a cached NixOS builder VM and asks once for the Nix daemon settings
   (a `sudo` prompt). nix-darwin users can enable `nix.linux-builder` instead.
   The hub checks the `builders` line in `nix config show`; it looks for an
   `aarch64-linux` entry.

   The `darwin.linux-builder` VM is a Nix **build service**, not a guest managed
   by OpenCodeBar. It is intentionally absent from the VMs list and has no
   start/stop controls in the app; its terminal must stay open while builds run.
   You can still read its captured console output under **Setup logs**.
3. **The signed helper** — `make hub` builds `OpenCodeBarVZ` and ad-hoc signs it
   with `com.apple.security.virtualization`. To rebuild it alone:

   ```sh
   make vz-helper
   ```

The VMs tab reports each prerequisite, with the command to fix it. Create is
disabled until all three are ready.

### Run setup from the app

The setup card has a **Run** button for the Nix installer and for rebuilding the
helper:

- **Install Nix** opens Terminal.app on the Mac and runs the official installer.
  Enter the Mac's administrator password in that Terminal window; the installer
  output streams into the VMs tab, and the capability check refreshes when it
  finishes. A GUI Terminal is required because macOS SIP blocks the installer's
  `/etc/fstab` step from a non-GUI process.
- **Build VM helper** runs `make vz-helper` locally and streams the Swift build
  and codesign output.
- The **Linux builder** command is copyable rather than runnable from the app:
  `nix --extra-experimental-features 'nix-command flakes' run nixpkgs#darwin.linux-builder` starts a long-lived builder VM and
  needs a terminal on the Mac. Run it once and leave it running.

The hub only exposes these fixed, allow-listed steps; clients cannot send
arbitrary commands.

#### Configure the builder

`nix ... darwin.linux-builder` only starts the builder VM; Nix still needs to be
told to use it. With the builder running in Terminal, add the builders entry and
SSH config from another Terminal window:

```sh
sudo mkdir -p /etc/nix /etc/ssh/ssh_config.d
sudo tee /etc/nix/machines >/dev/null <<'EOF'
ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 4 1 big-parallel,kvm,nixos-test - - - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=
EOF

sudo tee /etc/ssh/ssh_config.d/100-linux-builder.conf >/dev/null <<'EOF'
Host linux-builder
  Hostname localhost
  HostKeyAlias linux-builder
  Port 31022
  User builder
  IdentityFile /etc/nix/builder_ed25519
EOF

sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

The trailing base64 is the builder VM's publicly-known SSH host key. The Nix
installer already created `/etc/nix/builder_ed25519`. After the daemon restarts,
`nix config show` reports the builder and the VMs tab enables **Create**.

If you use nix-darwin, the supported alternative is
`nix.linux-builder.enable = true`, which starts the builder and writes these
settings for you.

Once Nix is configured, the VMs tab shows a read-only **Host build service**
card for the Linux builder. It stays outside the guest list because the hub does
not own the builder's lifecycle, and it is not counted as a machine. The card
copies the start command and opens the builder log. Its **Nix configured** chip
means the `builders` entry is present, not that the builder process is still
running; if builds fail, check the builder's Terminal window.

### Setup logs

Installer, helper-build, and Linux-builder output is stored on the hub host:

- `~/.local/share/opencodebar/vms/setup/nix.log`
- `~/.local/share/opencodebar/vms/setup/helper.log`
- `~/.local/share/opencodebar/vms/setup/builder.log` (captured
  `darwin.linux-builder` terminal output and builder configuration)

Each new run rotates the previous file to `nix-<timestamp>.log`,
`helper-<timestamp>.log`, or `builder-<timestamp>.log`, keeping the last ten per
step. The **Setup logs** button in the VMs tab opens the latest log for any of
the three steps, with copy and refresh. The same content is available at:

```text
GET /api/vms/setup/log?step=nix|helper|builder&tail=1200
GET /api/vms/setup/logs
```

Terminal may print shell-startup warnings before the installer output (for
example a missing tool referenced by `~/.zprofile` or `~/.zshrc`). Those lines
come from the Mac's shell, not from Nix, and do not affect the install.

Setup logs can contain the literal `Password:` prompt printed by `sudo`, but not
the password you type: `sudo` reads the password directly from the terminal with
echo disabled, so it never reaches the log file. Treat the logs like terminal
scrollback when sharing them; they can contain local paths and hostnames.

## Creating a guest

Open **VMs → +**. The create sheet is the **NixOS configuration builder**: it
starts with a recommended **Developer** preset and lets you click together a
complete machine before anything is written to disk.

### Machine basics

| Field | Notes |
| --- | --- |
| Name | Shown in the app; the guest hostname is derived from the opaque VM id |
| CPU | vCPU count, capped below the host's logical core count |
| Memory | Guest RAM in 1 GB steps |
| Disk | Raw disk size in GB; the image is sparse on APFS |
| NixOS channel | A flake ref such as `nixos-26.05`; also sets the initial `stateVersion` |
| Start after build | Boot the guest immediately after the image is ready |

### Configuration builder

The builder is shared by the Mac and iPhone/iPad apps and is driven by the
hub's catalog (`GET /api/vms/catalog`). Every card is metadata plus a small
NixOS module snippet, so the same selection always renders the same
`configuration.nix`.

- **Presets** — Minimal, Developer, Homelab, Media, AI Lab, Data Science, Web
  stack, Kubernetes, Desktop, Hardened, and Gaming. Applying a preset replaces
  the option selection but keeps your users, ports, and custom Nix.
- **Categories** — System, Users, Desktop, Development, Containers, Services,
  Networking, Media, AI, Monitoring, Security, Gaming, and Advanced.
- **Search** — Matches names, descriptions, tags, package attributes, and
  service names across every category. Try `docker`, `llm`, `media`, or
  `postgres`.
- **Dependencies and conflicts** — Selecting JupyterLab adds Python
  automatically. Selecting Docker replaces Podman, and choosing a different
  desktop session replaces the previous one. The build plan explains each
  change.
- **Users** — The `opencodebar` admin is always present with the hub's generated
  key. Add extra logins with a shell, groups, SSH public keys, passwordless
  sudo, and home-directory options.
- **System settings** — Time zone, locale, keyboard layout, the guest firewall,
  optional SSH password logins, and extra TCP/UDP ports.
- **Advanced** — Extra nixpkgs attributes, firewall ports, and a raw Nix module
  body. The raw body is appended verbatim; the preview shows exactly what will
  be written.
- **Live build plan** — A running summary of packages, services, open ports,
  users, warnings, and estimated size, plus a **Nix** tab with the rendered
  module and a copy button. Its `configuration.nix` preview is a request to
  `POST /api/vms/preview` (or `POST /api/vms/{id}/preview` for an existing VM),
  so it is the real output, not a client-side approximation.

The hub writes the configuration and flake, then runs:

```sh
nix build --extra-experimental-features 'nix-command flakes' \
  -L -o result .#packages.aarch64-linux.default
```

The flake exposes both `nixosConfigurations.<host>` and
`system.build.images.raw-efi`, so the host build and later in-guest rebuilds
share one `configuration.nix`. The resulting `.img` is copied to `disk.raw`
(sparse, using `cp -c` on APFS when possible). The detail page streams the build
log; the first build is the slow one.

Base packages are `curl`, `git`, `htop`, and `vim`. The generated configuration
also enables SSH key authentication only, a host-only NAT interface, a virtio
serial console, and a 200 MB journal cap.

## Lifecycle

| Action | Behaviour |
| --- | --- |
| **Start** | Boots the helper, waits for the VM to reach `running`, then discovers the DHCP address and waits for SSH |
| **Stop** | Asks the guest to shut down; forces the VM off after 30 seconds, then reaps the helper |
| **Restart** | Stop followed by start |
| **Pause / Resume** | Uses Virtualization.framework's pause and resume |
| **Rebuild** | Replaces the disk with a fresh image after a confirmation; everything inside the guest is lost |
| **Delete** | Stops the helper and removes the definition, disk, key, and logs |

Guests keep running when the hub exits or restarts. They are not stopped by the
app; use **Stop** when you are done. A failed build or unexpected guest shutdown
leaves the error on the VM page and in the logs.

## Monitoring

The list shows status, resources, the discovered address, build/boot progress,
pending package changes, and errors. The detail page adds:

- **CPU** and load from `/proc`, sampled over SSH.
- **Memory** and **disk** usage with bars.
- **Guest uptime**, hostname, kernel, and the current NixOS generation.
- **Helper CPU/RSS**, logical image size, and allocated bytes.
- **SSH** command and key path.
- **Last boot** and progress phases.

Guest metrics require SSH. Before the guest reaches SSH, use the serial console.
The hub samples at most every five seconds while a detail page is open.

## Serial console

**Console** attaches to the guest's virtio serial port (`hvc0`) through the
hub's authenticated WebSocket. It replays the last 64 KiB of the boot log when
opened, then streams live output; typing goes to the guest. This is the recovery
path when the network or SSH is misconfigured.

The serial console is not a graphical display. There is no VNC, GPU
acceleration, or USB passthrough.

## Changing a guest configuration

Open a VM and press **Configure** (Mac) or **Configure…** in the phone's menu.
The builder edits the stored definition:

- While the guest is **running**, the hub copies the generated
  `configuration.nix` to `/etc/nixos/configuration.nix` and runs
  `sudo nixos-rebuild switch` over SSH. Build output streams to the **Config**
  log.
- While the guest is **stopped**, the change is stored and applied after the
  next boot reaches SSH.
- While the image is **building**, the change is part of the image being built.
- CPU and memory can only change while the guest is stopped. Disk size and the
  NixOS channel are fixed at creation; use **Rebuild** for a fresh disk.

The older **Packages** tab still adds raw nixpkgs attributes. It uses the same
apply path and is useful for one-off packages that are not in the builder
catalog. Both the builder's extra packages and this list end up in
`environment.systemPackages`.

The guest needs network access to the Nix binary cache for a rebuild. If the
apply fails, the error is shown on the VM and in the log; the previous
generation keeps running.

To install something for a single session without changing the system, use the
SSH command from the detail page and `nix-shell -p <package>` inside the guest.
That state is not managed by the hub.

## Builder API

The catalog and preview endpoints are authenticated like every other hub route:

```text
GET  /api/vms/catalog
POST /api/vms/preview                 # render a definition before it exists
POST /api/vms/{id}/preview            # render against a real VM
PATCH /api/vms/{id}                   # body may include "config"
```

A builder configuration looks like this:

```json
{
  "version": 1,
  "preset": "developer",
  "enabled": ["zram", "docker", "tailscale", "neovim", "nodejs"],
  "settings": {
    "timezone": "UTC",
    "locale": "en_US.UTF-8",
    "keymap": "us",
    "firewall": true,
    "passwordAuthentication": false,
    "extraTCPPorts": [],
    "extraUDPPorts": []
  },
  "users": [],
  "extraPackages": ["ripgrep"],
  "extraConfig": ""
}
```

`enabled` holds catalog option ids. The hub expands `requires`, rejects
conflicts and unknown ids, and returns the rendered module plus the resolved
package/service/port plan. The full schema is in the
[API reference](../hub/api.md) under **Virtual machines**.

## Networking and SSH

Virtualization.framework gives each guest a host-only NAT address
(`192.168.64.x`). The hub discovers it from the host ARP table, falling back to
the DHCP address in the serial log. SSH is always port 22; there is no port
forwarding.

The VM page exposes a command like:

```sh
ssh -i ~/.local/share/opencodebar/vms/<id>/ssh/id_ed25519 opencodebar@192.168.64.x
```

Key authentication is required. The generated key is per VM and never leaves
the hub host except when you copy the command. `opencodebar` is in `wheel` and
`security.sudo.wheelNeedsPassword = false`, so `nixos-rebuild` can run
unattended. Treat anyone with the hub token and access to the VM directory as an
administrator of the guest.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Create is disabled | The setup card lists the missing helper, Nix, or Linux builder |
| **Run** starts but nothing happens | The Nix installer's password dialog is on the Mac. Unlock the Mac and look for it; if it was cancelled, press **Run** again |
| “doesn't have the virtualization entitlement” | Use **Build VM helper** in the setup card, or `make vz-helper` |
| Build fails immediately | Open the **Build** log; confirm the Linux builder is running and the channel exists |
| VM is running but no address | Open the **Console**; check DHCP and `ip addr` in the guest |
| SSH refused | Wait for boot, confirm the address, and check the serial console; the firewall allows SSH by default |
| Package apply fails | Open **Config**; the guest needs the Nix cache, and the previous generation stays active |
| Guest stopped unexpectedly | The serial log usually has the reason; rebuild if the disk is damaged |

## Limits

- Apple silicon only, macOS 14+.
- Image builds require Nix and an `aarch64-linux` builder.
- Rebuild replaces the disk; there are no snapshots, clones, suspend images, or
  resizing.
- No graphical console, GPU, USB, or VNC.
- The hub token controls VMs; helpers listen on loopback only.

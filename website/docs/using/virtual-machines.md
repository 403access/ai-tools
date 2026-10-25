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

### Setup logs

Installer and helper-build output is stored on the hub host:

- `~/.local/share/opencodebar/vms/setup/nix.log`
- `~/.local/share/opencodebar/vms/setup/helper.log`

Each new run rotates the previous file to `nix-<timestamp>.log` or
`helper-<timestamp>.log`, keeping the last ten per step. The **Setup logs**
button in the VMs tab opens the latest log for either step, with copy and
refresh. The same content is available at:

```text
GET /api/vms/setup/log?step=nix|helper&tail=1200
GET /api/vms/setup/logs
```

Terminal may print shell-startup warnings before the installer output (for
example a missing tool referenced by `~/.zprofile` or `~/.zshrc`). Those lines
come from the Mac's shell, not from Nix, and do not affect the install.

## Creating a guest

Open **VMs → +** and choose:

| Field | Notes |
| --- | --- |
| Name | Shown in the app; the guest hostname is derived from the opaque VM id |
| CPU | vCPU count, capped below the host's logical core count |
| Memory | Guest RAM in 1 GB steps |
| Disk | Raw disk size in GB; the image is sparse on APFS |
| NixOS channel | A flake ref such as `nixos-26.05`; also sets the initial `stateVersion` |
| Extra packages | Comma- or space-separated nixpkgs attributes, for example `nodejs, ripgrep` |
| Start after build | Boot the guest immediately after the image is ready |

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

## Installing software

Packages are declarative. Edit the list in **Packages**:

- While the guest is **running**, the hub copies the generated
  `configuration.nix` to `/etc/nixos/configuration.nix` and runs
  `sudo nixos-rebuild switch` over SSH. Build output streams to the **Config**
  log.
- While the guest is **stopped**, the change is stored and applied after the
  next boot reaches SSH.
- While the image is **building**, the change is part of the image being built.

The guest needs network access to the Nix binary cache for a rebuild. If the
apply fails, the error is shown on the VM and in the log; the previous
generation keeps running. The NixOS channel is fixed at creation; changing it
means rebuilding from a definition with a new channel.

To install something for a single session without changing the system, use the
SSH command from the detail page and `nix-shell -p <package>` inside the guest.
That state is not managed by the hub.

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

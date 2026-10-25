---
title: System monitor
sidebar_position: 5
---

# System monitor

The **System** tab shows the machine running OpenCodeBar Hub. It works from both
the Mac panel and the iPhone/iPad app, so you can check the host's health even
when you are away from it. The hub does the collection; the clients only render
its snapshot.

The tab polls every five seconds. Dynamic values update on each poll, while
expensive inventory scans are cached by the hub for five minutes. Use the
refresh button in the header (or pull to refresh on iOS) for an immediate
dynamic refresh.

## Overview and machine

Six tiles summarise the host: operating system, uptime, CPU, memory, free disk
space, and either battery or process count. The **Machine** card has the full
identifiers:

- hostname and computer name
- macOS version/build or Linux distribution and Windows edition
- kernel, architecture, model identifier, chip, and machine ID
- boot time, user, shell, timezone, and locale
- virtual-machine detection when the host is virtualised

## Media

The **Media** card shows what is currently playing on the host and which app owns
it. macOS reads the same MediaRemote item as Control Center, so Music, Spotify,
browsers, and other players all report the title, artist, album, elapsed time,
duration, and playback state. The card also uses system audio/video assertions to
catch apps that are playing media without publishing metadata; those rows show
the app and whether audio or video is active.

Paused items stay visible. When nothing is playing, the card says so instead of
staying hidden, so it doubles as a quick check that media monitoring is working.

The same card has playback controls: previous, back 15 seconds, play/pause,
forward 15 seconds, and next. Buttons only appear when the current player's
MediaRemote command list says they are supported, so a browser video may show
only play/pause while Music also shows track skipping. Controls always target the
system's current player.

Below the controls, **System output volume** has a mute toggle and a slider. It
changes the Mac's output volume through the system volume API, not the per-app
player volume. Volume and mute controls are available even when nothing is
playing.

All controls use the same authenticated hub connection as the rest of the panel.
The Mac app updates immediately from the control response; the next five-second
snapshot reconciles any player-specific delays.

## Processor and memory

The **Processor** card shows the CPU model, vendor, physical/logical core count,
clock speed, load averages, and overall usage. On machines where per-core usage
is available, a small bar chart shows each core. Thermal pressure and
temperature appear when the platform exposes them.

The **Memory** card separates used, free, and available memory, then breaks out
active, inactive, wired, and compressed pages. Swap usage appears whenever the
system has a swap device.

## Disks and network

Every mounted volume is listed with its filesystem, used/total capacity, and
free space. The first six appear by default; **Show all** reveals long lists such
as simulator volumes.

The **Network** card includes the default interface and gateway, DNS servers,
and each non-loopback interface with its IPv4/IPv6 addresses. A row can carry
multiple addresses; the MAC address is shown on the interface header.

## Power, security, and processes

The **Power & Security** card combines battery state (percentage, charging,
remaining time, health, cycles, condition, temperature) with thermal pressure
and the platform's security posture: SIP, FileVault, firewall, Gatekeeper,
SELinux, AppArmor, or Defender.

**Processes** switches between the top rows by CPU and by memory, showing PID,
user, and the selected metric for each process. The total process count is
shown above the list.

## Files

The **Files** card opens a read-only browser for the hub machine:

- quick links to Home, Root, Applications, Volumes, and the current OpenCode
  project folders
- breadcrumbs, an editable absolute path, and a parent-folder row
- a filter field and a hidden-file toggle
- text previews with selectable content, image previews, and file metadata
- file sizes, modification times, permissions, and symlink targets

Nothing can be edited, renamed, uploaded, or deleted. Hub and OpenCode credential
files are blocked from preview. Large folders are capped at 2,000 entries and
text previews at 512 KB; the UI says when either limit is reached.

On macOS the browser replaces the panel content so Back returns to the System
tab. On iOS it pushes onto the System navigation stack and keeps the standard
Back button.

## Installed apps and Homebrew

**Installed Apps** enumerates applications from the operating system:

- macOS: `system_profiler` inventory, including versions, bundle IDs, source,
  and architecture
- Linux: `.desktop` entries from system, user, Flatpak, and Snap directories
- Windows: registered applications from the uninstall registry keys

Type in the filter field to search names, bundle IDs, and paths. Long lists open
in pages with **Show all**.

**Homebrew** shows the installed version, prefix, formula and cask counts, and
how many packages are outdated. Outdated packages are marked with an amber dot
and sorted first, then formulae before casks. The full package list with versions
is available behind **Show all**.

## Developer tools, ports, containers, and displays

- **Developer Tools** lists detected runtimes and utilities — Node, Bun, Deno,
  Python, pip, Go, Rust, Cargo, Java, Swift, Ruby, PHP, Git, npm, pnpm, Yarn,
  Docker, kubectl, GitHub CLI, Clang, CMake, Make, SQLite, FFmpeg, Terraform,
  AWS CLI, and Google Cloud — with versions and paths.
- **Listening Ports** lists TCP listeners with the owning process and PID, which
  is useful for spotting a stray dev server.
- **Docker** appears when Docker is installed. It shows the client version and
  running containers, or notes that the daemon is not reachable.
- **Displays** lists GPUs and their monitors with resolutions and connection
  type.
- **Hub Process** reports the hub's own version, PID, runtime, uptime, port,
  memory, working directory, and SQLite database size.

## Platform support

macOS has the deepest coverage. Linux and Windows use their native equivalents
for OS identification, CPU/memory, disks, processes, battery, and network, with
optional sections omitted when a tool is unavailable. The endpoint behind this
tab is documented in the [API reference](../hub/api.md#health-and-info).

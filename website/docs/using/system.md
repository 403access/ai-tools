---
title: System monitor
sidebar_position: 5
---

# System monitor

The **System** tab shows the machine running OpenCodeBar Hub. It works from both
the Mac panel and the iPhone/iPad app, so you can check the host's health even
when you are away from it. On iOS, System shares the **Host** tab with
[Remote desktop](remote.md), which adds screen streaming and control. The hub
does the collection; the clients only render its snapshot. Terminals are the one
interactive exception in this tab: the hub proxies OpenCode's PTY sockets so both
apps can type into shells on the host.

The tab polls every five seconds. Dynamic values update on each poll, while
expensive inventory scans are cached by the hub for five minutes. Use the
refresh button in the header (or pull to refresh on iOS) for an immediate
dynamic refresh.

## Overview and machine

Six tiles summarise the host: operating system, uptime, CPU, memory, free disk
space, and either battery or process count. The **Memory** tile is interactive:
tap it on iOS or click it on the Mac to open a memory monitor with the page
breakdown, swap, and a searchable list of the largest processes. The **Machine**
card has the full identifiers:

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

## Terminals

The **Terminals** card lists pseudo-terminals owned by the OpenCode service on
the hub machine. It aggregates every OpenCode location it knows about, so a
shell started in the OpenCode TUI or in one project appears alongside the ones
started from OpenCodeBar. Each row shows:

- the terminal title, shell command, and working directory
- the owning project/location and the shell's PID
- whether it is running or has exited, including the exit code

Tap a terminal to open it. The Mac panel shows a resizable terminal window and
the phone presents a full-screen terminal sheet. Both are real terminal
emulators: arrow keys, Control/Alt sequences, `vim`, `htop`, password prompts,
and other interactive programs work. The terminal replays the recent output
OpenCode retained, then streams live output. Input is sent straight to the
shell, and resizing the window updates the PTY size on the host.

**New** starts another shell. Pick a project or type any absolute directory; the
shell starts there on the Mac. **Stop** (the stop-circle button) terminates the
shell and anything running inside it. Closing the terminal window only
disconnects — the shell keeps running for the next connection, and a
**Reconnect** button appears if the socket drops.

On the phone, the command field above the keyboard runs one line without
opening the terminal keyboard first. The SwiftTerm accessory row adds Control and
Escape keys for interactive programs.

Terminal traffic goes through the hub, so it works over the LAN or a tunnel
without exposing OpenCode's loopback service. Only the hub's Bearer token is
needed. The shell runs as the same macOS user as the hub, which makes the token
as powerful as that user's login — see [Security](../hub/security.md).

### Terminal.app tabs

macOS terminals do not expose the master side of their PTYs, so an existing
Terminal.app tab cannot be attached to as a byte stream. OpenCodeBar instead
lists the tabs that are already open and uses macOS automation for two things:

- reads the tab's visible screen as plain text, refreshed every second;
- runs a command in that tab, exactly like typing a line and pressing Return.

Open a tab from **Terminal.app** in the System tab to see the mirror. The
command field at the bottom sends a complete line; leaving it empty presses
Return. The **Focus** button brings that tab to the front on the Mac.

This is intentionally a mirror rather than a full emulator: there are no
colors, and individual keystrokes, arrow keys, or `Ctrl-C` are not forwarded.
It is useful for watching a build, reading a long-running command, or sending a
new command to a shell you already have open.

The hub must be allowed to control Terminal.app. On first use macOS asks for
Automation permission; approve it, or enable it later in **System Settings →
Privacy & Security → Automation**. If the permission is denied, the card shows
the error and a **Try again** button.

## Processor and memory

The **Processor** card shows the CPU model, vendor, physical/logical core count,
clock speed, load averages, and overall usage. On machines where per-core usage
is available, a small bar chart shows each core. Thermal pressure and
temperature appear when the platform exposes them.

The **Memory** card separates used, free, and available memory, then breaks out
active, inactive, wired, and compressed pages. Swap usage appears whenever the
system has a swap device. The full memory monitor, opened from the overview
tile, adds cached files, per-page bars, and a filterable process table with PID,
user, resident size, and percentage of physical memory.

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

## Installed apps, app details, and Homebrew

**Installed Apps** enumerates applications from the operating system:

- macOS: `system_profiler` inventory, including versions, bundle IDs, source,
  and architecture
- Linux: `.desktop` entries from system, user, Flatpak, and Snap directories
- Windows: registered applications from the uninstall registry keys

Type in the filter field to search names, bundle IDs, and paths. Long lists open
in pages with **Show all**.

Press an application to open its detail page. Alongside the icon and version it
shows the bundle ID, build, size, modification date, source, architecture,
minimum OS, executable, URL schemes, document types, bundled extensions, and
the signing authority. The folder button opens the bundle in the host file
browser.

Apps the hub knows how to inspect add their own sections. **Xcode** shows its
developer directory and installed SDKs, the frameworks shipped with its
platform toolchains, and every simulator runtime with its devices. Booted
simulators are marked and sorted first. From here you can boot, shut down,
erase, or delete a simulator, and remove a simulator runtime. Destructive
actions ask for confirmation and the list refreshes from the Mac immediately.

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

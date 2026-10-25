/**
 * System catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const SYSTEM_OPTIONS: CatalogOption[] = [
  option({
    id: "ssh",
    category: "system",
    name: "OpenSSH",
    summary: "Key-only remote login, used by the hub to apply changes",
    description:
      "OpenSSH is always enabled. The hub authorizes its generated ed25519 key for the opencodebar admin and never enables password logins unless you ask for them.",
    icon: "terminal.fill",
    tint: "running",
    locked: true,
    defaultOn: true,
    sizeMB: 18,
    services: ["OpenSSH"],
  }),
  option({
    id: "flakes",
    category: "system",
    name: "Flakes & nix-command",
    summary: "The modern Nix CLI that the generated flake uses",
    description:
      "Enables `nix-command` and `flakes`. The hub's flake and every in-guest rebuild depend on these experimental features.",
    icon: "snowflake",
    tint: "input",
    locked: true,
    defaultOn: true,
    sizeMB: 0,
  }),
  option({
    id: "optimise",
    category: "system",
    name: "Store optimisation",
    summary: "Deduplicate the Nix store automatically",
    description:
      "Runs the Nix store optimiser after builds. It keeps the guest image smaller with no runtime cost.",
    icon: "arrow.triangle.merge",
    tint: "output",
    locked: true,
    defaultOn: true,
    sizeMB: 0,
  }),
  option({
    id: "zram",
    category: "system",
    name: "zram swap",
    summary: "Compressed RAM swap for a small, fast guest",
    description:
      "Creates a compressed swap device in memory. It makes a 4 GB guest feel larger without growing the disk.",
    icon: "memorychip.fill",
    tint: "reasoning",
    defaultOn: true,
    sizeMB: 0,
    nix: `zramSwap = {
  enable = true;
  memoryPercent = 50;
};`,
  }),
  option({
    id: "nix-ld",
    category: "system",
    name: "nix-ld",
    summary: "Run prebuilt Linux binaries that expect /lib64",
    description:
      "Provides a dynamic loader shim so downloaded binaries, VS Code extensions, and language toolchains can run without patching.",
    icon: "link",
    tint: "input",
    sizeMB: 4,
    nix: `programs.nix-ld.enable = true;`,
  }),
  option({
    id: "fish",
    category: "system",
    name: "Fish shell",
    summary: "Friendly interactive shell with completions",
    description:
      "Enables Fish system-wide. Choose it as a login shell for any managed user in the Users step.",
    icon: "fish.fill",
    tint: "output",
    sizeMB: 22,
    nix: `programs.fish.enable = true;`,
  }),
  option({
    id: "zsh",
    category: "system",
    name: "Zsh",
    summary: "A powerful, extensible login shell",
    description:
      "Enables Zsh system-wide. Pair it with a managed user whose shell is set to zsh.",
    icon: "terminal",
    tint: "running",
    sizeMB: 18,
    nix: `programs.zsh.enable = true;`,
  }),
  option({
    id: "avahi",
    category: "system",
    name: "mDNS discovery",
    summary: "Advertise the guest as hostname.local",
    description:
      "Runs Avahi so the guest is discoverable as `<hostname>.local` on the LAN. Useful for services, printing, and Syncthing.",
    icon: "dot.radiowaves.left.and.right",
    tint: "running",
    sizeMB: 3,
    services: ["Avahi / mDNS"],
    nix: `services.avahi = {
  enable = true;
  nssmdns4 = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "flatpak",
    category: "system",
    name: "Flatpak",
    summary: "Install sandboxed desktop apps from Flathub",
    description:
      "Enables Flatpak and its portals. Useful on desktop guests, and harmless on headless ones.",
    icon: "square.stack.3d.up.fill",
    tint: "reasoning",
    sizeMB: 26,
    nix: `services.flatpak.enable = true;`,
  }),
  option({
    id: "printing",
    category: "system",
    name: "Printing",
    summary: "CUPS with mDNS printer discovery",
    description:
      "Enables CUPS and the Avahi printing helpers so network printers appear in desktop apps.",
    icon: "printer.fill",
    tint: "warn",
    sizeMB: 34,
    services: ["CUPS"],
    nix: `services.printing.enable = true;
services.avahi.enable = true;
services.avahi.nssmdns4 = true;`,
  }),
  option({
    id: "bluetooth",
    category: "system",
    name: "Bluetooth",
    summary: "Bluetooth stack and firmware hooks",
    description:
      "Enables the Bluetooth service. Virtualized guests only see a radio when the host passes one through.",
    icon: "wave.3.right.circle.fill",
    tint: "input",
    sizeMB: 12,
    nix: `hardware.bluetooth = {
  enable = true;
  powerOnBoot = true;
};`,
  }),
  option({
    id: "fstrim",
    category: "system",
    name: "Weekly trim",
    summary: "Discard unused blocks on the guest disk",
    description:
      "Runs fstrim on a timer. It keeps the sparse raw image small on the Mac.",
    icon: "scissors",
    tint: "output",
    sizeMB: 0,
    nix: `services.fstrim.enable = true;`,
  }),
  option({
    id: "locate",
    category: "system",
    name: "locate database",
    summary: "Fast filename search with updatedb",
    description:
      "Enables the locate database and a daily updatedb timer.",
    icon: "magnifyingglass",
    tint: "cacheRead",
    sizeMB: 4,
    nix: `services.locate.enable = true;`,
  }),
];

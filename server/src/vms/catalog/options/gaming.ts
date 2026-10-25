/**
 * Gaming catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const GAMING_OPTIONS: CatalogOption[] = [
  option({
    id: "steam",
    category: "gaming",
    name: "Steam",
    summary: "Steam and Proton for Linux gaming",
    description:
      "Enables Steam and the unfree package set. A virtualized GPU is required for anything beyond lightweight titles.",
    icon: "gamecontroller.fill",
    tint: "output",
    tags: ["Gaming", "GUI"],
    recommends: ["audio", "fonts"],
    unfree: true,
    services: ["Steam"],
    sizeMB: 2_100,
    nix: `programs.steam.enable = true;`,
  }),
  option({
    id: "minecraft",
    category: "gaming",
    name: "Minecraft server",
    summary: "A vanilla Java server on port 25565",
    description:
      "Runs the Minecraft server with the EULA accepted. Give it at least 4 GB of guest memory.",
    icon: "cube.fill",
    tint: "accent",
    tags: ["Server", "Gaming"],
    ports: [25565],
    services: ["Minecraft"],
    sizeMB: 420,
    nix: `services.minecraft-server = {
  enable = true;
  eula = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "retroarch",
    category: "gaming",
    name: "RetroArch + Lutris",
    summary: "Emulation and game launchers",
    description: "Installs RetroArch and Lutris. ROMs and installers are up to you.",
    icon: "arcade.stick.console.fill",
    tint: "reasoning",
    tags: ["Gaming", "GUI"],
    recommends: ["audio", "fonts"],
    packages: ["retroarch", "lutris"],
    sizeMB: 760,
  }),
];

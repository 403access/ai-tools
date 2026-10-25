/**
 * Desktop catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const DESKTOP_OPTIONS: CatalogOption[] = [
  option({
    id: "gnome",
    category: "desktop",
    name: "GNOME",
    summary: "A complete, beginner-friendly GNOME desktop",
    description:
      "GDM, GNOME Shell, and the standard GNOME app set. Pick a desktop guest when you need a graphical session inside the VM.",
    icon: "display",
    tint: "reasoning",
    tags: ["GUI", "Wayland"],
    badge: "Popular",
    conflicts: ["kde", "xfce", "hyprland"],
    recommends: ["audio", "fonts"],
    sizeMB: 2_400,
    services: ["GDM", "GNOME Shell"],
    nix: `services.xserver.enable = true;
services.displayManager.gdm.enable = true;
services.desktopManager.gnome.enable = true;`,
  }),
  option({
    id: "kde",
    category: "desktop",
    name: "KDE Plasma",
    summary: "Plasma 6 with SDDM and a familiar desktop",
    description:
      "KDE Plasma 6, SDDM, and the KDE application suite. It is heavier than GNOME but very configurable.",
    icon: "rectangle.3.group.fill",
    tint: "input",
    tags: ["GUI", "Wayland"],
    conflicts: ["gnome", "xfce", "hyprland"],
    recommends: ["audio", "fonts"],
    sizeMB: 2_800,
    services: ["SDDM", "Plasma 6"],
    nix: `services.xserver.enable = true;
services.displayManager.sddm.enable = true;
services.desktopManager.plasma6.enable = true;`,
  }),
  option({
    id: "xfce",
    category: "desktop",
    name: "XFCE",
    summary: "A light desktop for small VMs",
    description:
      "XFCE with LightDM. It is the best choice when the guest has 4 GB of memory or less.",
    icon: "rectangle.split.3x3.fill",
    tint: "output",
    tags: ["GUI", "Lightweight"],
    conflicts: ["gnome", "kde", "hyprland"],
    recommends: ["audio", "fonts"],
    sizeMB: 1_100,
    services: ["LightDM", "XFCE"],
    nix: `services.xserver.enable = true;
services.xserver.desktopManager.xfce.enable = true;
services.xserver.displayManager.lightdm.enable = true;`,
  }),
  option({
    id: "hyprland",
    category: "desktop",
    name: "Hyprland",
    summary: "A tiling Wayland compositor",
    description:
      "Hyprland with SDDM's Wayland session. Bring your own dotfiles; the default keymap is intentionally spartan.",
    icon: "rectangle.split.2x2.fill",
    tint: "reasoning",
    tags: ["GUI", "Wayland", "Tiling"],
    conflicts: ["gnome", "kde", "xfce"],
    recommends: ["audio", "fonts"],
    sizeMB: 950,
    services: ["SDDM", "Hyprland"],
    nix: `programs.hyprland.enable = true;
services.xserver.enable = true;
services.displayManager.sddm.enable = true;
services.displayManager.sddm.wayland.enable = true;`,
  }),
  option({
    id: "audio",
    category: "desktop",
    name: "PipeWire audio",
    summary: "Modern audio and screen-sharing support",
    description:
      "PipeWire with ALSA and PulseAudio compatibility. Desktop apps and browsers expect it.",
    icon: "speaker.wave.2.fill",
    tint: "warn",
    sizeMB: 38,
    services: ["PipeWire"],
    nix: `services.pipewire = {
  enable = true;
  alsa.enable = true;
  alsa.support32Bit = true;
  pulse.enable = true;
};`,
  }),
  option({
    id: "fonts",
    category: "desktop",
    name: "Font pack",
    summary: "DejaVu, Liberation, Noto, and emoji",
    description:
      "A broad font set that makes a graphical guest, browser, and office suite look right out of the box.",
    icon: "textformat",
    tint: "cacheWrite",
    sizeMB: 320,
    nix: `fonts.packages = with pkgs; [
  dejavu_fonts
  liberation_ttf
  noto-fonts
  noto-fonts-emoji
];`,
  }),
  option({
    id: "firefox",
    category: "desktop",
    name: "Firefox",
    summary: "The privacy-friendly browser",
    description: "Installs Mozilla Firefox with the standard NixOS wrapper.",
    icon: "globe",
    tint: "warn",
    tags: ["App"],
    packages: ["firefox"],
    sizeMB: 310,
  }),
  option({
    id: "chromium",
    category: "desktop",
    name: "Chromium",
    summary: "A second browser for testing",
    description: "Installs Chromium for web testing and a Chrome-like profile.",
    icon: "globe.americas.fill",
    tint: "running",
    tags: ["App"],
    packages: ["chromium"],
    sizeMB: 370,
  }),
  option({
    id: "libreoffice",
    category: "desktop",
    name: "LibreOffice",
    summary: "Documents, spreadsheets, and slides",
    description: "Installs the full LibreOffice suite.",
    icon: "doc.richtext.fill",
    tint: "input",
    tags: ["App", "Office"],
    packages: ["libreoffice"],
    sizeMB: 720,
  }),
  option({
    id: "gimp",
    category: "desktop",
    name: "GIMP",
    summary: "Photo editing and image manipulation",
    description: "Installs GIMP and its common plugins.",
    icon: "photo.fill",
    tint: "output",
    tags: ["App", "Creative"],
    packages: ["gimp"],
    sizeMB: 350,
  }),
  option({
    id: "obs",
    category: "desktop",
    name: "OBS Studio",
    summary: "Screen recording and streaming",
    description: "Installs OBS Studio. Screen capture inside a VM may be limited by the guest GPU.",
    icon: "record.circle",
    tint: "danger",
    tags: ["App", "Creative"],
    packages: ["obs-studio"],
    sizeMB: 390,
  }),
  option({
    id: "vlc",
    category: "desktop",
    name: "VLC",
    summary: "Play almost any media format",
    description: "Installs VLC media player.",
    icon: "play.circle.fill",
    tint: "warn",
    tags: ["App", "Media"],
    packages: ["vlc"],
    sizeMB: 180,
  }),
];

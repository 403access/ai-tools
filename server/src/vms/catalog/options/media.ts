/**
 * Media catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const MEDIA_OPTIONS: CatalogOption[] = [
  option({
    id: "jellyfin",
    category: "media",
    name: "Jellyfin",
    summary: "A self-hosted media server",
    description:
      "Runs Jellyfin on 8096 with its setup wizard. Add media folders under /srv/media from the console.",
    icon: "play.rectangle.fill",
    tint: "warn",
    tags: ["Media", "Self-hosted"],
    ports: [8096],
    services: ["Jellyfin"],
    sizeMB: 380,
    nix: `services.jellyfin = {
  enable = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "navidrome",
    category: "media",
    name: "Navidrome",
    summary: "A personal music streaming server",
    description:
      "Runs Navidrome on 4533. Point it at a music folder in the web UI after first boot.",
    icon: "music.note.house.fill",
    tint: "reasoning",
    tags: ["Music", "Self-hosted"],
    ports: [4533],
    services: ["Navidrome"],
    sizeMB: 95,
    nix: `services.navidrome = {
  enable = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "ffmpeg",
    category: "media",
    name: "Media toolkit",
    summary: "ffmpeg, ImageMagick, and Plex-style transcoding tools",
    description: "Command-line tools for converting video, audio, and images.",
    icon: "film.stack.fill",
    tint: "output",
    tags: ["CLI", "Media"],
    packages: ["ffmpeg", "imagemagick"],
    sizeMB: 340,
  }),
  option({
    id: "yt-dlp",
    category: "media",
    name: "yt-dlp",
    summary: "Download media from the command line",
    description: "Installs yt-dlp, the actively maintained youtube-dl fork.",
    icon: "arrow.down.circle.fill",
    tint: "danger",
    tags: ["CLI", "Media"],
    packages: ["yt-dlp"],
    sizeMB: 38,
  }),
];

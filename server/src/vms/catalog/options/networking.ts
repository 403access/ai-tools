/**
 * Networking catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const NETWORKING_OPTIONS: CatalogOption[] = [
  option({
    id: "tailscale",
    category: "networking",
    name: "Tailscale",
    summary: "Private mesh access from anywhere",
    description:
      "Enables Tailscale and trusts its interface. Run `tailscale up` in the guest console once to join your tailnet.",
    icon: "point.3.connected.trianglepath.dotted",
    tint: "running",
    tags: ["VPN", "Remote"],
    badge: "Popular",
    services: ["Tailscale"],
    sizeMB: 60,
    nix: `services.tailscale = {
  enable = true;
  openFirewall = true;
};
networking.firewall.trustedInterfaces = [ "tailscale0" ];`,
  }),
  option({
    id: "nginx",
    category: "networking",
    name: "Nginx",
    summary: "A production web server on port 80",
    description:
      "Runs Nginx with a small default page. Edit the generated configuration to add real virtual hosts.",
    icon: "server.rack",
    tint: "output",
    tags: ["Web", "Reverse proxy"],
    ports: [80, 443],
    conflicts: ["caddy"],
    services: ["Nginx"],
    sizeMB: 42,
    nix: `services.nginx = {
  enable = true;
  recommendedGzipSettings = true;
  recommendedOptimisation = true;
  recommendedProxySettings = true;
  recommendedTlsSettings = true;
};
services.nginx.virtualHosts."default" = {
  listen = [ { addr = "0.0.0.0"; port = 80; } ];
  locations."/" = {
    return = "200 'OpenCodeBar NixOS is ready'";
  };
};`,
  }),
  option({
    id: "caddy",
    category: "networking",
    name: "Caddy",
    summary: "Automatic HTTPS and a simple reverse proxy",
    description:
      "Runs Caddy with a starter virtual host. It is a compact alternative to Nginx and handles TLS automatically.",
    icon: "lock.rectangle.stack.fill",
    tint: "accent",
    tags: ["Web", "Reverse proxy"],
    ports: [80, 443],
    conflicts: ["nginx"],
    services: ["Caddy"],
    sizeMB: 55,
    nix: `services.caddy = {
  enable = true;
  virtualHosts.":80".extraConfig = ''
    respond "OpenCodeBar NixOS is ready"
  '';
};
networking.firewall.allowedTCPPorts = [ 80 443 ];`,
  }),
];

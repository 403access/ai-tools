/**
 * Services catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const SERVICE_OPTIONS: CatalogOption[] = [
  option({
    id: "postgresql",
    category: "services",
    name: "PostgreSQL",
    summary: "A local database with an `app` database and owner",
    description:
      "Runs PostgreSQL, creates the `app` database, and makes it reachable on port 5432 from the host-only network.",
    icon: "cylinder.split.1x2.fill",
    tint: "input",
    tags: ["Database"],
    ports: [5432],
    services: ["PostgreSQL"],
    sizeMB: 260,
    nix: `services.postgresql = {
  enable = true;
  enableTCPIP = true;
  ensureDatabases = [ "app" ];
  ensureUsers = [
    {
      name = "app";
      ensureDBOwnership = true;
    }
  ];
};
networking.firewall.allowedTCPPorts = [ 5432 ];`,
  }),
  option({
    id: "redis",
    category: "services",
    name: "Redis",
    summary: "An in-memory cache and queue",
    description: "Runs a Redis server on 6379 with the default `default` instance.",
    icon: "bolt.fill",
    tint: "danger",
    tags: ["Database", "Cache"],
    ports: [6379],
    services: ["Redis"],
    sizeMB: 32,
    nix: `services.redis.servers."default" = {
  enable = true;
  port = 6379;
};
networking.firewall.allowedTCPPorts = [ 6379 ];`,
  }),
  option({
    id: "mariadb",
    category: "services",
    name: "MariaDB",
    summary: "A MySQL-compatible SQL server",
    description: "Runs MariaDB on 3306. It is a good fit for web apps that expect MySQL.",
    icon: "cylinder.fill",
    tint: "warn",
    tags: ["Database"],
    ports: [3306],
    services: ["MariaDB"],
    sizeMB: 290,
    nix: `services.mysql = {
  enable = true;
  package = pkgs.mariadb;
};
networking.firewall.allowedTCPPorts = [ 3306 ];`,
  }),
  option({
    id: "gitea",
    category: "services",
    name: "Gitea",
    summary: "A lightweight self-hosted Git forge",
    description:
      "Runs Gitea on port 3000 with SQLite storage. Create the first admin account in the browser.",
    icon: "arrow.triangle.branch",
    tint: "output",
    tags: ["Git", "Self-hosted"],
    ports: [3000],
    services: ["Gitea"],
    sizeMB: 210,
    nix: `services.gitea = {
  enable = true;
  settings.server = {
    DOMAIN = "localhost";
    HTTP_PORT = 3000;
    ROOT_URL = "http://localhost:3000/";
  };
};
networking.firewall.allowedTCPPorts = [ 3000 ];`,
  }),
  option({
    id: "syncthing",
    category: "services",
    name: "Syncthing",
    summary: "Peer-to-peer file sync with a web UI",
    description:
      "Runs Syncthing for the admin user with its discovery and relay ports open. Pair it with a folder on the Mac.",
    icon: "arrow.triangle.2.circlepath",
    tint: "running",
    tags: ["Files", "Self-hosted"],
    ports: [8384, 22000],
    services: ["Syncthing"],
    sizeMB: 140,
    nix: `services.syncthing = {
  enable = true;
  openDefaultPorts = true;
};`,
  }),
  option({
    id: "samba",
    category: "services",
    name: "Samba share",
    summary: "A guest-writable SMB share at /srv/share",
    description:
      "Runs Samba with a permissive `share` export. Use it to move files between the Mac and the guest.",
    icon: "folder.badge.gearshape",
    tint: "warn",
    tags: ["Files", "SMB"],
    ports: [139, 445],
    services: ["Samba"],
    sizeMB: 180,
    nix: `services.samba = {
  enable = true;
  openFirewall = true;
  settings = {
    global = {
      workgroup = "WORKGROUP";
      "server string" = "OpenCodeBar";
      "map to guest" = "Bad User";
    };
    share = {
      path = "/srv/share";
      browseable = "yes";
      "read only" = "no";
      "guest ok" = "yes";
    };
  };
};
systemd.tmpfiles.rules = [ "d /srv/share 0775 root root -" ];`,
  }),
  option({
    id: "home-assistant",
    category: "services",
    name: "Home Assistant",
    summary: "Local home automation on port 8123",
    description:
      "Runs Home Assistant with its onboarding wizard. It is happiest with at least 2 GB of guest memory.",
    icon: "house.fill",
    tint: "accent",
    tags: ["Home", "Self-hosted"],
    ports: [8123],
    services: ["Home Assistant"],
    sizeMB: 460,
    nix: `services.home-assistant = {
  enable = true;
  openFirewallForComponents = true;
};
networking.firewall.allowedTCPPorts = [ 8123 ];`,
  }),
  option({
    id: "vaultwarden",
    category: "services",
    name: "Vaultwarden",
    summary: "A tiny Bitwarden-compatible password vault",
    description:
      "Runs Vaultwarden on 8222 with signups enabled for first-run setup. Put it behind Tailscale or Caddy for remote use.",
    icon: "key.fill",
    tint: "danger",
    tags: ["Security", "Self-hosted"],
    ports: [8222],
    services: ["Vaultwarden"],
    sizeMB: 120,
    nix: `services.vaultwarden = {
  enable = true;
  config = {
    ROCKET_ADDRESS = "0.0.0.0";
    ROCKET_PORT = 8222;
    SIGNUPS_ALLOWED = "true";
  };
};
networking.firewall.allowedTCPPorts = [ 8222 ];`,
  }),
  option({
    id: "n8n",
    category: "services",
    name: "n8n",
    summary: "Workflow automation with a visual editor",
    description: "Runs n8n on port 5678. It is a local Zapier-style automation server.",
    icon: "point.3.connected.trianglepath.dotted",
    tint: "reasoning",
    tags: ["Automation", "Self-hosted"],
    ports: [5678],
    services: ["n8n"],
    sizeMB: 330,
    nix: `services.n8n = {
  enable = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "minio",
    category: "services",
    name: "MinIO",
    summary: "S3-compatible object storage",
    description:
      "Runs MinIO with the API on 9000 and the console on 9001. The default credentials are shown in its docs; change them before exposing it.",
    icon: "externaldrive.fill.badge.icloud",
    tint: "output",
    tags: ["Storage", "Self-hosted"],
    ports: [9000, 9001],
    services: ["MinIO"],
    sizeMB: 210,
    nix: `services.minio = {
  enable = true;
  listenAddress = "0.0.0.0:9000";
  consoleAddress = "0.0.0.0:9001";
};
networking.firewall.allowedTCPPorts = [ 9000 9001 ];`,
  }),
];

/**
 * Security catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const SECURITY_OPTIONS: CatalogOption[] = [
  option({
    id: "fail2ban",
    category: "security",
    name: "Fail2ban",
    summary: "Ban repeated SSH authentication failures",
    description:
      "Watches the journal and bans abusive addresses. It is low-cost insurance for a guest reachable on a LAN or tailnet.",
    icon: "shield.lefthalf.filled",
    tint: "danger",
    tags: ["Hardening", "SSH"],
    services: ["Fail2ban"],
    sizeMB: 18,
    nix: `services.fail2ban.enable = true;`,
  }),
  option({
    id: "clamav",
    category: "security",
    name: "ClamAV",
    summary: "Antivirus scanning with freshclam updates",
    description:
      "Runs the ClamAV daemon and signature updater. It adds a sizeable signature database to the image.",
    icon: "ant.fill",
    tint: "warn",
    tags: ["Hardening", "Antivirus"],
    services: ["ClamAV"],
    sizeMB: 520,
    nix: `services.clamav = {
  daemon.enable = true;
  updater.enable = true;
};`,
  }),
  option({
    id: "tor",
    category: "security",
    name: "Tor",
    summary: "Route traffic through the Tor network",
    description:
      "Runs the Tor client service. Applications must be configured to use the SOCKS proxy on 9050.",
    icon: "network",
    tint: "reasoning",
    tags: ["Privacy", "Proxy"],
    ports: [9050],
    services: ["Tor"],
    sizeMB: 42,
    nix: `services.tor = {
  enable = true;
  client.enable = true;
};`,
  }),
  option({
    id: "apparmor",
    category: "security",
    name: "AppArmor",
    summary: "Mandatory access control for services",
    description:
      "Enables AppArmor profiles and confines services that ship with one.",
    icon: "lock.shield.fill",
    tint: "danger",
    tags: ["Hardening"],
    services: ["AppArmor"],
    sizeMB: 8,
    nix: `security.apparmor = {
  enable = true;
  killUnconfinedConfinables = true;
};`,
  }),
  option({
    id: "auditd",
    category: "security",
    name: "auditd",
    summary: "Kernel-level auditing of security events",
    description: "Enables the Linux audit daemon and the NixOS audit rules.",
    icon: "list.bullet.rectangle.portrait.fill",
    tint: "danger",
    tags: ["Hardening", "Audit"],
    services: ["auditd"],
    sizeMB: 12,
    nix: `security.auditd.enable = true;
security.audit.enable = true;`,
  }),
  option({
    id: "firejail",
    category: "security",
    name: "Firejail",
    summary: "Run untrusted apps in a sandbox",
    description: "Installs Firejail for ad-hoc sandboxing of desktop and CLI applications.",
    icon: "shield.checkered",
    tint: "warn",
    tags: ["Sandbox", "CLI"],
    packages: ["firejail"],
    sizeMB: 30,
  }),
  option({
    id: "gnupg",
    category: "security",
    name: "GnuPG & secrets",
    summary: "gpg, age, and sops",
    description: "Installs the standard tools for signing, encrypting, and managing secrets.",
    icon: "key.horizontal.fill",
    tint: "danger",
    tags: ["Crypto", "CLI"],
    packages: ["gnupg", "age", "sops"],
    sizeMB: 64,
  }),
];

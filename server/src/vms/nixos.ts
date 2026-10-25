import type {
  NixOSBuilderConfig,
  NixOSManagedUser,
  VirtualMachine,
  VMConfigPreview,
} from "./types.ts";
import { hostnameFor, newVMID } from "./store.ts";
import { VMValidationError } from "./errors.ts";
import {
  DEFAULT_PACKAGES,
  effectivePackages,
  nixString,
  normalizePackages,
  packageExpression,
} from "./packages.ts";
import {
  CATEGORIES,
  defaultBuilderConfig,
  normalizeBuilderConfig,
  optionCount,
  resolveBuilderConfig,
  type ResolvedBuilderConfig,
} from "./catalog/index.ts";

export { VMValidationError } from "./errors.ts";
export {
  DEFAULT_PACKAGES,
  effectivePackages,
  normalizePackages,
} from "./packages.ts";

export const DEFAULT_CHANNEL = process.env.OPENCODEBAR_NIXOS_CHANNEL?.trim() || "nixos-26.05";

const CHANNEL_NAME = /^(nixos|nixpkgs)-[A-Za-z0-9._-]+$/;

export function validateVMName(value: unknown): string {
  if (typeof value !== "string") throw new VMValidationError("A name is required");
  const trimmed = value.trim();
  // The name is shown in the UI and embedded in a Nix string, so reject control
  // characters before collapsing ordinary whitespace.
  if (/[\u0000-\u001f\u007f]/.test(trimmed)) {
    throw new VMValidationError("The name contains unsupported control characters");
  }
  const name = trimmed.replace(/\s+/g, " ");
  if (!name) throw new VMValidationError("A name is required");
  if (name.length > 64) throw new VMValidationError("Keep the name to 64 characters or fewer");
  return name;
}

export function normalizeChannel(value: unknown): string {
  if (value === undefined || value === null || value === "") return DEFAULT_CHANNEL;
  if (typeof value !== "string") throw new VMValidationError("The NixOS channel must be a string");
  const channel = value.trim();
  if (!CHANNEL_NAME.test(channel)) {
    throw new VMValidationError("Use a channel such as nixos-26.05 or nixpkgs-unstable");
  }
  return channel;
}

/** NixOS stateVersion captured at creation; it should not follow channel bumps. */
export function stateVersionFor(channel: string): string {
  const match = /^nixos-(\d{2}\.\d{2})/.exec(channel);
  return match?.[1] ?? "26.05";
}

function indent(text: string, spaces = 2): string {
  const pad = " ".repeat(spaces);
  return text
    .split("\n")
    .map((line) => (line.trim() ? `${pad}${line}` : ""))
    .join("\n");
}

function renderOptionSections(resolved: ResolvedBuilderConfig): string {
  const sections: string[] = [];
  for (const category of CATEGORIES) {
    const entries = resolved.options.filter(
      (entry) => entry.category === category.id && entry.nix.trim(),
    );
    if (entries.length === 0) continue;
    const body = entries.map((entry) => indent(entry.nix.trim())).join("\n\n");
    sections.push(`  # ${category.name}\n${body}`);
  }
  return sections.join("\n\n");
}

function shellPackage(shell: NixOSManagedUser["shell"]): string {
  switch (shell) {
    case "zsh":
      return "pkgs.zsh";
    case "fish":
      return "pkgs.fish";
    default:
      return "pkgs.bash";
  }
}

function renderManagedUsers(
  config: NixOSBuilderConfig,
  vm: VirtualMachine,
): string {
  const primary = `  # The hub connects as this user with the generated key and applies changes over SSH.
  users.users.opencodebar = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      ${nixString(vm.ssh.publicKey)}
    ];
  };`;

  const users = config.users.map((user) => {
    const groups = [...new Set(user.groups)].filter(Boolean);
    const lines = [
      `  users.users.${user.name} = {`,
      "    isNormalUser = true;",
      `    description = ${nixString(user.description)};`,
      `    createHome = ${user.createHome ? "true" : "false"};`,
      `    shell = ${shellPackage(user.shell)};`,
    ];
    if (groups.length > 0) {
      lines.push(`    extraGroups = [ ${groups.map((group) => nixString(group)).join(" ")} ];`);
    }
    if (user.sshKeys.length > 0) {
      lines.push("    openssh.authorizedKeys.keys = [");
      for (const key of user.sshKeys) lines.push(`      ${nixString(key)}`);
      lines.push("    ];");
    }
    lines.push("  };");
    return lines.join("\n");
  });

  const sudoUsers = config.users
    .filter((user) => user.passwordlessSudo && !user.groups.includes("wheel"))
    .map((user) => user.name);
  const sudoRule = sudoUsers.length > 0
    ? `\n  security.sudo.extraRules = [\n${sudoUsers
        .map(
          (name) =>
            `    { users = [ ${nixString(name)} ]; commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ]; }`,
        )
        .join("\n")}\n  ];`
    : "";

  return [primary, ...users].join("\n\n") + sudoRule;
}

function renderPackages(packages: string[]): string {
  const list = packages
    .sort((a, b) => a.localeCompare(b))
    .map(packageExpression)
    .join("\n");
  return `  environment.systemPackages = [\n${list}\n  ];`;
}

function portList(ports: number[]): string {
  return `[ ${ports.join(" ")} ]`;
}

/**
 * The guest configuration is the single source of truth for packages, users,
 * services, and system settings. It is written into the image at build time and
 * copied to the guest before `nixos-rebuild switch` when anything changes.
 *
 * File systems and the boot loader are `mkDefault` so the image variant can
 * provide the same values without conflicting.
 *
 * The third argument is optional so the original two-argument call sites keep
 * rendering a valid minimal configuration.
 */
export function renderConfiguration(
  vm: VirtualMachine,
  packages: string[],
  config?: NixOSBuilderConfig | null,
): string {
  const normalized = normalizeBuilderConfig(config ?? vm.config ?? defaultBuilderConfig());
  const resolved = resolveBuilderConfig(normalized);
  const allPackages = effectivePackages(resolved.packages, packages);
  const settings = resolved.config.settings;
  const hostname = hostnameFor(vm.id);
  const optionSections = renderOptionSections(resolved);
  const users = renderManagedUsers(resolved.config, vm);

  const firewallPorts: string[] = [];
  if (settings.extraTCPPorts.length > 0) {
    firewallPorts.push(
      `  networking.firewall.allowedTCPPorts = ${portList(settings.extraTCPPorts)};`,
    );
  }
  if (settings.extraUDPPorts.length > 0) {
    firewallPorts.push(
      `  networking.firewall.allowedUDPPorts = ${portList(settings.extraUDPPorts)};`,
    );
  }

  const advanced = resolved.config.extraConfig.trim();
  const advancedBlock = advanced
    ? `\n  # Advanced module body (from the builder)\n${indent(advanced)}\n`
    : "";

  return `# Managed by OpenCodeBar · ${vm.id}
# Edit this in the Configure step or in the generated Nix preview. Manual changes
# here are overwritten the next time the configuration is applied.
{ config, lib, pkgs, modulesPath, ... }:
{
  # Virtualization.framework attaches virtio block, network, RNG, and console
  # devices. This profile puts the drivers in the initrd so the disk is visible
  # before the real root is mounted.
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  system.stateVersion = ${nixString(vm.stateVersion)};

  networking.hostName = ${nixString(hostname)};
  networking.usePredictableInterfaceNames = false;
  networking.useDHCP = true;
  networking.firewall.enable = ${settings.firewall ? "true" : "false"};

  # Virtualization.framework attaches a raw disk with an ESP and one ext4 root.
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
  boot.growPartition = lib.mkDefault true;
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault false;
  boot.loader.timeout = lib.mkDefault 1;

  # Virtualization.framework attaches a virtio console (hvc0); ttyAMA0 is kept
  # for a PL011-capable kernel. Both give the VMs tab a boot log and an
  # emergency shell before SSH is up.
  boot.kernelParams = [ "console=ttyAMA0,115200" "console=hvc0" ];
  systemd.services."serial-getty@ttyAMA0".enable = true;
  systemd.services."serial-getty@hvc0".enable = true;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = ${settings.passwordAuthentication ? "true" : "false"};
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

${users}
  # The hub applies declarative changes over SSH. Only the keys above are
  # authorized, and the VM is on a host-only NAT network.
  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
${resolved.unfree ? "\n  nixpkgs.config.allowUnfree = true;\n" : ""}
  services.journald.extraConfig = "SystemMaxUse=200M";
  documentation.enable = false;
  time.timeZone = ${nixString(settings.timezone)};
  i18n.defaultLocale = ${nixString(settings.locale)};
  console.keyMap = ${nixString(settings.keymap)};
${firewallPorts.length > 0 ? `\n${firewallPorts.join("\n")}\n` : ""}${optionSections ? `\n${optionSections}\n` : ""}${advancedBlock}
  # The image variant imports disk-size-option.nix. Setting this on the base
  # system would be an unknown option during an in-guest nixos-rebuild, so it
  # lives in the deferred image module instead.
  image.modules.raw-efi = {
    virtualisation.diskSize = ${Math.max(8, Math.round(vm.diskGB)) * 1024};
  };

${renderPackages(allPackages)}
}
`;
}

/**
 * A flake that exposes both the running system (for `nixos-rebuild switch`) and
 * the raw EFI image used by Virtualization.framework.
 */
export function renderFlake(vm: VirtualMachine): string {
  const hostname = hostnameFor(vm.id);
  return `{
  description = ${nixString(`OpenCodeBar virtual machine ${vm.name}`)};

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/${vm.channel}";

  outputs = { self, nixpkgs }: {
    nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [ ./configuration.nix ];
    };

    # nix build .#packages.aarch64-linux.default produces the raw EFI image.
    packages.aarch64-linux.default =
      self.nixosConfigurations.${hostname}.config.system.build.images.raw-efi;
  };
}
`;
}

/** Attribute passed to `nix build` on the host. */
export const IMAGE_ATTRIBUTE = ".#packages.aarch64-linux.default";

/** Hostname/flake attribute for the guest, derived from the VM id. */
export function guestHostname(vm: VirtualMachine): string {
  return hostnameFor(vm.id);
}

/** Builds the live build plan shown in the builder's Review pane. */
export function previewConfiguration(
  vm: VirtualMachine,
  input: { config?: unknown; packages?: unknown } = {},
): VMConfigPreview {
  const config = normalizeBuilderConfig(input.config ?? vm.config ?? defaultBuilderConfig());
  const resolved = resolveBuilderConfig(config);
  const packages = normalizePackages(input.packages);
  const configuration = renderConfiguration(vm, packages, resolved.config);
  return {
    configuration,
    flake: renderFlake(vm),
    packages: effectivePackages(resolved.packages, packages).sort((a, b) => a.localeCompare(b)),
    services: resolved.services,
    ports: resolved.ports,
    users: ["opencodebar", ...resolved.config.users.map((user) => user.name)],
    optionCount: optionCount(resolved.config),
    added: resolved.added,
    warnings: resolved.warnings,
    sizeMB: resolved.sizeMB,
    stateVersion: vm.stateVersion,
  };
}

/** Preview a configuration before a VM exists (used by the create sheet). */
export function previewDraftConfiguration(input: {
  config?: unknown;
  packages?: unknown;
  name?: string;
  diskGB?: number;
  stateVersion?: string;
  channel?: string;
}): VMConfigPreview {
  const id = newVMID();
  const channel = normalizeChannel(input.channel);
  const now = Date.now();
  const vm: VirtualMachine = {
    id,
    name: typeof input.name === "string" && input.name.trim() ? input.name.trim() : "NixOS",
    distro: "nixos",
    channel,
    stateVersion:
      typeof input.stateVersion === "string" && input.stateVersion.trim()
        ? input.stateVersion.trim()
        : stateVersionFor(channel),
    arch: "aarch64",
    status: "stopped",
    createdAt: now,
    updatedAt: now,
    cpuCount: 4,
    memoryMB: 4_096,
    diskGB:
      typeof input.diskGB === "number" && Number.isFinite(input.diskGB)
        ? Math.min(Math.max(input.diskGB, 8), 512)
        : 20,
    packages: [],
    pendingPackages: [],
    pendingConfig: false,
    config: defaultBuilderConfig(),
    lastError: null,
    progress: null,
    ssh: {
      user: "opencodebar",
      keyPath: "/tmp/opencodebar-preview/ssh/id_ed25519",
      publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPREVIEW opencodebar-preview",
    },
    network: { mac: "52:54:00:00:00:00", ip: null, reachable: false },
    paths: {
      directory: "/tmp/opencodebar-preview",
      disk: "/tmp/opencodebar-preview/disk.raw",
      configuration: "/tmp/opencodebar-preview/configuration.nix",
      flake: "/tmp/opencodebar-preview/flake.nix",
      serialLog: "/tmp/opencodebar-preview/serial.log",
      buildLog: "/tmp/opencodebar-preview/build.log",
      applyLog: "/tmp/opencodebar-preview/apply.log",
      runtime: "/tmp/opencodebar-preview/runtime.json",
    },
    metrics: null,
  };
  return previewConfiguration(vm, input);
}

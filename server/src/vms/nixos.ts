import type { VirtualMachine } from "./types.ts";
import { hostnameFor } from "./store.ts";

/** Packages every managed NixOS guest gets for basic administration. */
export const DEFAULT_PACKAGES = ["curl", "git", "htop", "vim"];

export const DEFAULT_CHANNEL = process.env.OPENCODEBAR_NIXOS_CHANNEL?.trim() || "nixos-26.05";

const PACKAGE_NAME = /^[A-Za-z0-9][A-Za-z0-9._+-]*$/;
const CHANNEL_NAME = /^(nixos|nixpkgs)-[A-Za-z0-9._-]+$/;

export class VMValidationError extends Error {
  constructor(message: string, readonly status = 400) {
    super(message);
    this.name = "VMValidationError";
  }
}

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

export function normalizePackages(value: unknown): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new VMValidationError("Packages must be an array of names");
  const unique = new Set<string>();
  for (const entry of value) {
    if (typeof entry !== "string") {
      throw new VMValidationError("Packages must be an array of names", 400);
    }
    const name = entry.trim();
    if (!name) continue;
    if (!PACKAGE_NAME.test(name)) {
      throw new VMValidationError(`Invalid Nix package name: ${name}`);
    }
    unique.add(name);
  }
  return [...unique];
}

export function effectivePackages(...lists: string[][]): string[] {
  const unique = new Set<string>();
  for (const list of lists) {
    for (const name of list) unique.add(name);
  }
  return [...unique];
}

function nixString(value: string): string {
  const escaped = value
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\$\{/g, "\\${");
  return `"${escaped}"`;
}

/**
 * The guest configuration is the single source of truth for packages and
 * services. It is written into the image at build time, and copied to the guest
 * before `nixos-rebuild switch` when packages change.
 *
 * File systems and the boot loader are `mkDefault` so the image variant can
 * provide the same values without conflicting; a plain guest rebuild still gets
 * them because nothing else defines those options.
 */
/** Renders one nixpkgs attribute path, including names that need quoting. */
function packageExpression(name: string): string {
  const path = name
    .split(".")
    .map((part) => nixString(part))
    .join(" ");
  return `      (lib.getAttrFromPath [ ${path} ] pkgs)`;
}

export function renderConfiguration(vm: VirtualMachine, packages: string[]): string {
  const hostname = hostnameFor(vm.id);
  const packageList = effectivePackages(DEFAULT_PACKAGES, packages)
    .sort((a, b) => a.localeCompare(b))
    .map(packageExpression)
    .join("\n");

  return `# Managed by OpenCodeBar · ${vm.id}
# Changes made here are overwritten when packages are edited in the VMs tab.
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
  networking.firewall.enable = true;

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
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.opencodebar = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      ${nixString(vm.ssh.publicKey)}
    ];
  };
  # The hub applies declarative changes over SSH. Only the key above is
  # authorized, and the VM is on a host-only NAT network.
  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;

  services.journald.extraConfig = "SystemMaxUse=200M";
  documentation.enable = false;
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # The image variant imports disk-size-option.nix. Setting this on the base
  # system would be an unknown option during an in-guest nixos-rebuild, so it
  # lives in the deferred image module instead.
  image.modules.raw-efi = {
    virtualisation.diskSize = ${Math.max(8, Math.round(vm.diskGB)) * 1024};
  };

  environment.systemPackages = [
${packageList}
  ];
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

/**
 * Validation and normalization for builder configs arriving from the API or
 * from disk.
 */

import { VMValidationError } from "../errors.ts";
import { normalizePackages } from "../packages.ts";
import type {
  NixOSBuilderConfig,
  NixOSManagedUser,
} from "../types.ts";
import { DEFAULT_SETTINGS, defaultBuilderConfig } from "./defaults.ts";
import { OPTION_BY_ID } from "./options/index.ts";
import { PRESETS } from "./presets.ts";
import { LIMITS } from "./settings.ts";

const USER_NAME = /^[a-z_][a-z0-9_-]{0,31}$/;
const GROUP_NAME = /^[a-z_][a-z0-9_-]{0,31}$/;
const SSH_KEY = /^(ssh|ecdsa|sk-ssh|sk-ecdsa)-[A-Za-z0-9@._-]+ [A-Za-z0-9+/=]+/;
const RESERVED_USERS = new Set(["root", "opencodebar", "nobody", "daemon", "systemd-network"]);

function text(value: unknown, fallback: string, max: number): string {
  if (value === undefined || value === null) return fallback;
  if (typeof value !== "string") throw new VMValidationError("Expected a string");
  const trimmed = value.trim();
  if (!trimmed) return fallback;
  if (trimmed.length > max) throw new VMValidationError(`Keep this value to ${max} characters or fewer`);
  if (/[\u0000-\u001f\u007f]/.test(trimmed)) {
    throw new VMValidationError("Control characters are not supported here");
  }
  return trimmed;
}

function boolean(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function portList(value: unknown, label: string): number[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new VMValidationError(`${label} must be an array of ports`);
  if (value.length > LIMITS.maxPorts) {
    throw new VMValidationError(`Use ${LIMITS.maxPorts} ${label} or fewer`);
  }
  const unique = new Set<number>();
  for (const entry of value) {
    const port = typeof entry === "string" ? Number.parseInt(entry, 10) : entry;
    if (typeof port !== "number" || !Number.isInteger(port) || port < 1 || port > 65_535) {
      throw new VMValidationError(`${label} must contain TCP/UDP ports from 1 to 65535`);
    }
    unique.add(port);
  }
  return [...unique].sort((a, b) => a - b);
}

function userList(value: unknown): NixOSManagedUser[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new VMValidationError("Users must be an array");
  if (value.length > LIMITS.maxUsers) {
    throw new VMValidationError(`Use ${LIMITS.maxUsers} users or fewer`);
  }
  const seen = new Set<string>();
  return value.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new VMValidationError(`User ${index + 1} is malformed`);
    }
    const source = entry as Record<string, unknown>;
    const name = typeof source.name === "string" ? source.name.trim().toLowerCase() : "";
    if (!USER_NAME.test(name)) {
      throw new VMValidationError(
        "User names must start with a lowercase letter or underscore and use a-z, 0-9, _ or -",
      );
    }
    if (RESERVED_USERS.has(name)) {
      throw new VMValidationError(`The user name ${name} is reserved`);
    }
    if (seen.has(name)) throw new VMValidationError(`The user ${name} is listed twice`);
    seen.add(name);

    const groups = source.groups === undefined || source.groups === null
      ? []
      : Array.isArray(source.groups)
        ? source.groups
        : (() => {
            throw new VMValidationError(`Groups for ${name} must be an array`);
          })();
    const normalizedGroups = new Set<string>();
    for (const group of groups) {
      if (typeof group !== "string" || !GROUP_NAME.test(group.trim())) {
        throw new VMValidationError(`Invalid group name for ${name}`);
      }
      normalizedGroups.add(group.trim());
    }

    const keys = source.sshKeys === undefined || source.sshKeys === null
      ? []
      : Array.isArray(source.sshKeys)
        ? source.sshKeys
        : (() => {
            throw new VMValidationError(`SSH keys for ${name} must be an array`);
          })();
    if (keys.length > 10) throw new VMValidationError(`Keep 10 SSH keys or fewer for ${name}`);
    const normalizedKeys: string[] = [];
    for (const key of keys) {
      if (typeof key !== "string") throw new VMValidationError(`SSH keys for ${name} must be strings`);
      const trimmed = key.trim();
      if (!trimmed) continue;
      if (trimmed.length > 4_096 || !SSH_KEY.test(trimmed)) {
        throw new VMValidationError(`“${trimmed.slice(0, 24)}…” is not an OpenSSH public key`);
      }
      normalizedKeys.push(trimmed);
    }

    const shell = source.shell === undefined ? "bash" : source.shell;
    if (shell !== "bash" && shell !== "zsh" && shell !== "fish") {
      throw new VMValidationError(`Choose bash, zsh, or fish as the shell for ${name}`);
    }

    return {
      name,
      description: text(source.description, name, 80),
      groups: [...normalizedGroups],
      shell,
      sshKeys: normalizedKeys,
      passwordlessSudo: boolean(source.passwordlessSudo, false),
      createHome: boolean(source.createHome, true),
    };
  });
}

function settingObject(value: unknown): Record<string, unknown> {
  if (value === undefined || value === null) return {};
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new VMValidationError("settings must be an object");
  }
  return value as Record<string, unknown>;
}

/**
 * Validates and normalizes a builder config from the API or from disk. Unknown
 * option ids are rejected so a typo never produces a half-configured guest.
 * Pass `lenient` when reading an older definition so an option removed from the
 * catalog does not make the whole VM disappear.
 */
export function normalizeBuilderConfig(value: unknown, lenient = false): NixOSBuilderConfig {
  if (value === undefined || value === null) return defaultBuilderConfig();
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new VMValidationError("The configuration must be an object");
  }
  const source = value as Record<string, unknown>;
  const settings = settingObject(source.settings);

  const enabled: string[] = [];
  if (source.enabled !== undefined && source.enabled !== null) {
    if (!Array.isArray(source.enabled)) {
      throw new VMValidationError("enabled must be an array of option ids");
    }
    for (const entry of source.enabled) {
      if (typeof entry !== "string") throw new VMValidationError("enabled must contain option ids");
      const id = entry.trim();
      if (!id) continue;
      const option = OPTION_BY_ID.get(id);
      if (!option) {
        if (lenient) continue;
        throw new VMValidationError(`Unknown configuration option: ${id}`);
      }
      if (!option.locked && !enabled.includes(id)) enabled.push(id);
    }
  }

  const preset = typeof source.preset === "string" && PRESETS.some((entry) => entry.id === source.preset)
    ? source.preset
    : null;

  const timezone = text(settings.timezone, DEFAULT_SETTINGS.timezone, 64);
  if (!/^[A-Za-z][A-Za-z0-9_+-]*(?:\/[A-Za-z0-9_+-]+)*$/.test(timezone)) {
    throw new VMValidationError("Choose a time zone such as UTC or Europe/Berlin");
  }
  const locale = text(settings.locale, DEFAULT_SETTINGS.locale, 40);
  if (!/^[a-z]{2,3}_[A-Z]{2}\.UTF-8$/.test(locale)) {
    throw new VMValidationError("Choose a locale such as en_US.UTF-8");
  }
  const keymap = text(settings.keymap, DEFAULT_SETTINGS.keymap, 24);
  if (!/^[a-z0-9-]+$/.test(keymap)) {
    throw new VMValidationError("Choose a keyboard layout such as us or de");
  }

  const extraConfig = typeof source.extraConfig === "string" ? source.extraConfig : "";
  if (extraConfig.length > LIMITS.maxExtraConfigBytes) {
    throw new VMValidationError(
      `Keep custom Nix to ${Math.round(LIMITS.maxExtraConfigBytes / 1_000)} KB or less`,
    );
  }
  if (extraConfig.includes("\u0000")) throw new VMValidationError("Custom Nix contains a NUL byte");

  const extraPackages = normalizePackages(source.extraPackages);
  if (extraPackages.length > LIMITS.maxExtraPackages) {
    throw new VMValidationError(`Use ${LIMITS.maxExtraPackages} extra packages or fewer`);
  }

  return {
    version: 1,
    preset,
    enabled,
    settings: {
      timezone,
      locale,
      keymap,
      firewall: boolean(settings.firewall, DEFAULT_SETTINGS.firewall),
      passwordAuthentication: boolean(
        settings.passwordAuthentication,
        DEFAULT_SETTINGS.passwordAuthentication,
      ),
      extraTCPPorts: portList(settings.extraTCPPorts, "TCP ports"),
      extraUDPPorts: portList(settings.extraUDPPorts, "UDP ports"),
    },
    users: userList(source.users),
    extraPackages,
    extraConfig,
  };
}

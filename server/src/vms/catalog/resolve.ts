/**
 * Turns a validated builder config into the flat plan the API and the NixOS
 * renderer consume.
 */

import { VMValidationError } from "../errors.ts";
import { DEFAULT_PACKAGES, effectivePackages } from "../packages.ts";
import type { NixOSBuilderConfig } from "../types.ts";
import { OPTION_BY_ID, OPTIONS } from "./options/index.ts";
import type { CatalogOption } from "./types.ts";

export interface ResolvedBuilderConfig {
  config: NixOSBuilderConfig;
  /** Ids added because another enabled option requires them. */
  added: string[];
  packages: string[];
  services: string[];
  ports: number[];
  warnings: string[];
  sizeMB: number;
  unfree: boolean;
  /** Enabled catalog options in catalog order, excluding locked options. */
  options: CatalogOption[];
}

/**
 * Expands requirements, checks conflicts, and flattens every enabled option
 * into the package, service, and port lists the UI shows in its build plan.
 */
export function resolveBuilderConfig(config: NixOSBuilderConfig): ResolvedBuilderConfig {
  const enabled = new Set(config.enabled.filter((id) => {
    const option = OPTION_BY_ID.get(id);
    return option !== undefined && !option.locked;
  }));
  const added: string[] = [];

  // Expand requirements breadth-first so nested dependencies appear too.
  const queue = [...enabled];
  while (queue.length > 0) {
    const id = queue.shift()!;
    const entry = OPTION_BY_ID.get(id);
    if (!entry) continue;
    for (const requirement of entry.requires) {
      if (enabled.has(requirement)) continue;
      const required = OPTION_BY_ID.get(requirement);
      if (!required) continue;
      enabled.add(requirement);
      added.push(requirement);
      queue.push(requirement);
    }
  }

  const options = OPTIONS.filter((entry) => enabled.has(entry.id) && !entry.locked);
  const conflicts = new Map<string, string>();
  for (const entry of options) {
    for (const other of entry.conflicts) {
      if (enabled.has(other)) {
        conflicts.set(entry.id, other);
        conflicts.set(other, entry.id);
      }
    }
  }
  if (conflicts.size > 0) {
    const [left, right] = [...conflicts.entries()][0]!;
    const leftName = OPTION_BY_ID.get(left)?.name ?? left;
    const rightName = OPTION_BY_ID.get(right)?.name ?? right;
    throw new VMValidationError(`${leftName} cannot be combined with ${rightName}`);
  }

  const packages = effectivePackages(
    DEFAULT_PACKAGES,
    config.extraPackages,
    ...options.map((entry) => entry.packages),
  ).sort((a, b) => a.localeCompare(b));

  const services = [...new Set(options.flatMap((entry) => entry.services))];
  const ports = [
    ...new Set([
      ...config.settings.extraTCPPorts,
      ...config.settings.extraUDPPorts,
      ...options.flatMap((entry) => entry.ports),
    ]),
  ].sort((a, b) => a - b);

  const warnings: string[] = [];
  const desktop = options.find((entry) =>
    ["gnome", "kde", "xfce", "hyprland"].includes(entry.id),
  );
  if (desktop) {
    warnings.push(`${desktop.name} needs at least 4 GB of guest memory for a smooth session.`);
  }
  if (options.some((entry) => entry.id === "ollama")) {
    warnings.push("Local models need RAM and disk. Start with a 3B model or smaller.");
  }
  if (config.settings.passwordAuthentication) {
    warnings.push(
      "SSH password authentication is on, but managed users have no passwords yet. Set one from the serial console.",
    );
  }
  if (config.users.some((user) => user.passwordlessSudo && !user.groups.includes("wheel"))) {
    warnings.push("A non-wheel user has passwordless sudo. Review that rule before exposing the guest.");
  }

  const sizeMB = 1_024 + options.reduce((total, entry) => total + entry.sizeMB, 0);

  return {
    config: { ...config, enabled: [...enabled] },
    added,
    packages,
    services,
    ports,
    warnings,
    sizeMB,
    unfree: options.some((entry) => entry.unfree),
    options,
  };
}

export function optionCount(config: NixOSBuilderConfig): number {
  return config.enabled.filter((id) => {
    const entry = OPTION_BY_ID.get(id);
    return entry !== undefined && !entry.locked;
  }).length;
}

import { VMValidationError } from "./errors.ts";

/** Packages every managed NixOS guest gets for basic administration. */
export const DEFAULT_PACKAGES = ["curl", "git", "htop", "vim"];

const PACKAGE_NAME = /^[A-Za-z0-9][A-Za-z0-9._+-]*$/;

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

export function nixString(value: string): string {
  const escaped = value
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\$\{/g, "\\${");
  return `"${escaped}"`;
}

/**
 * Renders one nixpkgs attribute path, including names that need quoting.
 * `python3Packages.requests` becomes `lib.getAttrFromPath [ "python3Packages"
 * "requests" ] pkgs`, which is safe for every attribute name.
 */
export function packageExpression(name: string): string {
  const path = name
    .split(".")
    .map((part) => nixString(part))
    .join(" ");
  return `      (lib.getAttrFromPath [ ${path} ] pkgs)`;
}

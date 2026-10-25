import type { CatalogOption } from "./types.ts";

/**
 * Builds a catalog option, defaulting every optional field so each entry only
 * states what makes it different from its neighbours.
 */
export const option = (
  value: Omit<CatalogOption, "description" | "tint" | "tags" | "badge" | "packages" | "requires" | "recommends" | "conflicts" | "ports" | "services" | "defaultOn" | "locked" | "sizeMB" | "unfree" | "nix"> &
    Partial<CatalogOption>,
): CatalogOption => ({
  description: value.summary,
  tint: "accent",
  tags: [],
  badge: null,
  packages: [],
  requires: [],
  recommends: [],
  conflicts: [],
  ports: [],
  services: [],
  defaultOn: false,
  locked: false,
  sizeMB: 0,
  unfree: false,
  nix: "",
  ...value,
});

/**
 * Catalog types shared by the option groups, the resolver, and the client.
 */

import type { VMConfigOption } from "../types.ts";

export interface CatalogOption extends VMConfigOption {
  /** NixOS module body. It is indented and inserted into the guest module. */
  nix: string;
}

/**
 * The payload behind `GET /api/vms/catalog`: the same data the hub uses to
 * render a guest, minus the NixOS module bodies the client never needs.
 */

import type { VMConfigCatalog } from "../types.ts";
import { CATEGORIES } from "./categories.ts";
import { defaultBuilderConfig } from "./defaults.ts";
import { OPTIONS } from "./options/index.ts";
import { PRESETS } from "./presets.ts";
import {
  COMMON_GROUPS,
  KEYMAPS,
  LIMITS,
  LOCALES,
  SHELLS,
  TIMEZONES,
} from "./settings.ts";

export function catalogForClient(): VMConfigCatalog {
  return {
    version: 1,
    categories: CATEGORIES,
    options: OPTIONS.map(({ nix: _nix, ...entry }) => entry),
    presets: PRESETS,
    defaults: defaultBuilderConfig(),
    recommendedPreset: "developer",
    shells: [...SHELLS],
    groups: COMMON_GROUPS,
    timezones: TIMEZONES,
    locales: LOCALES,
    keymaps: KEYMAPS,
    limits: LIMITS,
  };
}

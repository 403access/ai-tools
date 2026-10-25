/**
 * The NixOS configuration catalog.
 *
 * Every entry is a small, declarative unit the apps can render as a card:
 * metadata for the UI plus the NixOS module lines and nixpkgs attributes the
 * hub writes into `configuration.nix`. Keeping the catalog here (instead of in
 * Swift) means the macOS app, the iPhone app, and the REST API always offer the
 * same options and the same rendered result.
 *
 * The catalog is split by concern:
 *
 * - `categories.ts` and `options/` hold the cards and the NixOS snippets.
 * - `presets.ts`, `settings.ts`, and `defaults.ts` hold the starter choices.
 * - `validate.ts` and `resolve.ts` turn a submitted config into a build plan.
 * - `client.ts` shapes the payload for `GET /api/vms/catalog`.
 */

export { CATEGORIES, categoryById } from "./categories.ts";
export { OPTIONS, optionById } from "./options/index.ts";
export { PRESETS } from "./presets.ts";
export {
  COMMON_GROUPS,
  KEYMAPS,
  LIMITS,
  LOCALES,
  SHELLS,
  TIMEZONES,
} from "./settings.ts";
export {
  DEFAULT_SETTINGS,
  defaultBuilderConfig,
  recommendedBuilderConfig,
} from "./defaults.ts";
export { catalogForClient } from "./client.ts";
export { normalizeBuilderConfig } from "./validate.ts";
export { optionCount, resolveBuilderConfig } from "./resolve.ts";
export type { ResolvedBuilderConfig } from "./resolve.ts";
export type { CatalogOption } from "./types.ts";

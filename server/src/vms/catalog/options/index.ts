/**
 * Every catalog option, grouped by category and concatenated in the order the
 * UI renders its sections.
 */

import type { CatalogOption } from "../types.ts";
import { SYSTEM_OPTIONS } from "./system.ts";
import { DESKTOP_OPTIONS } from "./desktop.ts";
import { DEVELOPMENT_OPTIONS } from "./development.ts";
import { CONTAINER_OPTIONS } from "./containers.ts";
import { SERVICE_OPTIONS } from "./services.ts";
import { NETWORKING_OPTIONS } from "./networking.ts";
import { MEDIA_OPTIONS } from "./media.ts";
import { AI_OPTIONS } from "./ai.ts";
import { OBSERVABILITY_OPTIONS } from "./observability.ts";
import { SECURITY_OPTIONS } from "./security.ts";
import { GAMING_OPTIONS } from "./gaming.ts";

export const OPTIONS: CatalogOption[] = [
  ...SYSTEM_OPTIONS,
  ...DESKTOP_OPTIONS,
  ...DEVELOPMENT_OPTIONS,
  ...CONTAINER_OPTIONS,
  ...SERVICE_OPTIONS,
  ...NETWORKING_OPTIONS,
  ...MEDIA_OPTIONS,
  ...AI_OPTIONS,
  ...OBSERVABILITY_OPTIONS,
  ...SECURITY_OPTIONS,
  ...GAMING_OPTIONS,
];

export const OPTION_BY_ID = new Map(OPTIONS.map((entry) => [entry.id, entry]));

export function optionById(id: string): CatalogOption | undefined {
  return OPTION_BY_ID.get(id);
}

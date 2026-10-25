/**
 * Compatibility barrel for the system monitor. The implementation lives in
 * `./system/` so each platform collector stays small and independently testable.
 */
export { SystemInfoService } from "./system/index.ts";
export { MediaControlError } from "./system/media.ts";
export { findExecutable } from "./system/commands.ts";
export { parseBrewVersions } from "./system/homebrew.ts";
export { parseDF } from "./system/storage.ts";
export { summarizeProcesses } from "./system/processes.ts";
export { platformName } from "./system/util.ts";
export type {
  CommandResult,
  CommandRunner,
  SystemInfoOptions,
} from "./system/types.ts";

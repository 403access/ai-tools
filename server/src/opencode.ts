/**
 * OpenCode service integration, split by responsibility:
 * discovery, HTTP client, errors, and Go usage lookups.
 */
export { discoverOpenCode } from "./opencode/discovery.ts";
export { OpenCodeClient, type SessionsOptions } from "./opencode/client.ts";
export { GoUsageError, OpenCodeError, type OpenCodeLocation } from "./opencode/errors.ts";
export { fetchGoUsage } from "./opencode/usage.ts";

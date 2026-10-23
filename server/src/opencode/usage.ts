import type { HubConfig } from "../config.ts";
import type { GoUsage } from "../types.ts";
import { GoUsageError } from "./errors.ts";

/**
 * Fetches the three Go plan windows from the console usage endpoint. Cloudflare
 * rejects requests without a conventional user agent.
 */
export async function fetchGoUsage(config: HubConfig, key: string): Promise<GoUsage> {
  let response: Response;
  try {
    response = await fetch(config.goUsageURL, {
      headers: {
        Authorization: `Bearer ${key}`,
        Accept: "application/json",
        "User-Agent": "OpenCodeBar-Hub (+https://github.com/403access/ai-tools)",
      },
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    throw new GoUsageError(
      `Could not reach the Go usage endpoint: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  if (response.status === 401) {
    throw new GoUsageError("Go API key expired — create a new one in Console");
  }
  if (!response.ok) {
    throw new GoUsageError(`Console returned HTTP ${response.status}`);
  }

  let body: { usage?: GoUsage };
  try {
    body = (await response.json()) as { usage?: GoUsage };
  } catch {
    throw new GoUsageError("Unexpected usage response");
  }
  if (!body.usage) throw new GoUsageError("Unexpected usage response");
  return body.usage;
}

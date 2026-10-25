import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig, writeHubConfig } from "../src/config.ts";

function withTempDirs(run: (env: NodeJS.ProcessEnv) => void): void {
  const directory = mkdtempSync(join(tmpdir(), "opencodebar-config-"));
  const env = { XDG_CONFIG_HOME: directory, XDG_DATA_HOME: directory };
  try {
    run(env);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

describe("hub config", () => {
  test("defaults the event throttle to one coalescing window", () => {
    withTempDirs((env) => {
      expect(loadConfig(env).eventThrottleMs).toBe(250);
    });
  });

  test("persists the event throttle and reloads it", () => {
    withTempDirs((env) => {
      const config = loadConfig(env);
      config.eventThrottleMs = 750;
      writeHubConfig(config);

      expect(loadConfig(env).eventThrottleMs).toBe(750);
    });
  });

  test("lets the environment override the saved throttle", () => {
    withTempDirs((env) => {
      const config = loadConfig(env);
      config.eventThrottleMs = 750;
      writeHubConfig(config);

      const overridden = loadConfig({ ...env, OPENCODEBAR_EVENT_THROTTLE_MS: "1000" });
      expect(overridden.eventThrottleMs).toBe(1_000);
    });
  });

  test("defaults sleep prevention off and persists it", () => {
    withTempDirs((env) => {
      expect(loadConfig(env).preventSleep).toBe(false);

      const config = loadConfig(env);
      config.preventSleep = true;
      writeHubConfig(config);

      expect(loadConfig(env).preventSleep).toBe(true);
    });
  });

  test("lets the environment override the saved sleep preference", () => {
    withTempDirs((env) => {
      const config = loadConfig(env);
      config.preventSleep = true;
      writeHubConfig(config);

      const overridden = loadConfig({ ...env, OPENCODEBAR_PREVENT_SLEEP: "off" });
      expect(overridden.preventSleep).toBe(false);
    });
  });

  test("clamps out-of-range values", () => {
    withTempDirs((env) => {
      expect(loadConfig({ ...env, OPENCODEBAR_EVENT_THROTTLE_MS: "-50" }).eventThrottleMs).toBe(0);
      expect(loadConfig({ ...env, OPENCODEBAR_EVENT_THROTTLE_MS: "99999" }).eventThrottleMs).toBe(5_000);
    });
  });
});

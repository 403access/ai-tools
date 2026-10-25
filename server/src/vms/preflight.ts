import { arch, cpus, totalmem } from "node:os";
import { defaultRunner, findExecutable } from "../system/commands.ts";
import type { CommandRunner } from "../system/types.ts";
import { findVZHelper } from "./helper.ts";
import { DEFAULT_CHANNEL } from "./nixos.ts";
import type { VMCapabilities } from "./types.ts";

const NIX_DIRECTORIES = [
  "/nix/var/nix/profiles/default/bin",
  "/run/current-system/sw/bin",
  `${process.env.HOME ?? ""}/.nix-profile/bin`,
];

export interface PreflightOptions {
  runner?: CommandRunner;
  env?: NodeJS.ProcessEnv;
  storageDir: string;
}

export interface PreflightResult {
  capabilities: VMCapabilities;
  nixPath: string | null;
  helperPath: string | null;
}

/** Locates Nix even when the hub was launched from a GUI without a login shell. */
export function findNix(env: NodeJS.ProcessEnv = process.env): string | null {
  const override = env.OPENCODEBAR_NIX?.trim();
  if (override) return override;
  return findExecutable("nix", NIX_DIRECTORIES.filter(Boolean)) ?? null;
}

function firstLine(value: string): string {
  return value.split(/\r?\n/).map((line) => line.trim()).find(Boolean) ?? "";
}

/** Reads the builder list from `nix config show`, with a fallback for older Nix. */
async function linuxBuilderDetail(runner: CommandRunner, nixPath: string): Promise<{
  available: boolean;
  detail: string | null;
}> {
  let output: string | null = null;
  for (const args of [["config", "show"], ["show-config"]]) {
    const result = await runner(nixPath, args, 12_000);
    if (result.ok) {
      output = result.stdout;
      break;
    }
  }
  if (output === null) {
    return {
      available: false,
      detail: "Could not read the Nix configuration to check for a Linux builder.",
    };
  }

  const builderLine = output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) => line.startsWith("builders"));
  const value = builderLine?.includes("=") ? builderLine.slice(builderLine.indexOf("=") + 1).trim() : "";
  const available = value.split(/\s+/).includes("aarch64-linux");
  return {
    available,
    detail: available
      ? null
      : "No aarch64-linux builder is configured. Building a NixOS image on Apple silicon needs one, for example `nix run nixpkgs#darwin.linux-builder` or nix-darwin's `nix.linux-builder.enable`.",
  };
}

/**
 * Answers "can this hub host run a NixOS VM, and what is missing?". The check is
 * deliberately read-only: installing Nix or enabling a Linux builder requires
 * the user's sudo password, so the UI shows the commands instead.
 */
export async function preflight(options: PreflightOptions): Promise<PreflightResult> {
  const env = options.env ?? process.env;
  const runner = options.runner ?? defaultRunner;
  const helperPath = findVZHelper(env);
  const nixPath = findNix(env);
  const notes: string[] = [];
  let helperEntitled = false;

  const supported = process.platform === "darwin" && arch() === "arm64";
  if (!supported) {
    notes.push("Virtual machines require an Apple silicon Mac running macOS 14 or later.");
  }
  if (!helperPath) {
    notes.push("The OpenCodeBarVZ helper is missing. Run `make vz-helper` (or `make hub`, which builds it).");
  } else {
    const signed = await runner(
      "codesign",
      ["-d", "--entitlements", ":-", helperPath],
      5_000,
    );
    helperEntitled =
      signed.ok &&
      /com\.apple\.security\.virtualization/.test(`${signed.stdout}\n${signed.stderr}`);
    if (!helperEntitled) {
      notes.push(
        "The helper is missing the virtualization entitlement. Run `make vz-helper` so it is ad-hoc signed with com.apple.security.virtualization.",
      );
    }
  }

  let nixVersion: string | null = null;
  let linuxBuilder = false;
  let linuxBuilderInfo: string | null = null;

  if (!nixPath) {
    notes.push("Nix is not installed, so NixOS images cannot be built. Install it from https://nixos.org/download.");
  } else {
    const version = await runner(nixPath, ["--version"], 8_000);
    nixVersion = firstLine(version.stdout) || firstLine(version.stderr) || null;
    const builder = await linuxBuilderDetail(runner, nixPath);
    linuxBuilder = builder.available;
    linuxBuilderInfo = builder.detail;
    if (!linuxBuilder && builder.detail) notes.push(builder.detail);
  }

  if (helperPath && nixPath && linuxBuilder) {
    notes.push("Ready to build and run NixOS guests with Apple's Virtualization.framework.");
  }

  const cpuTotal = Math.max(1, cpus().length);
  const memoryTotalMB = Math.max(2_048, Math.floor(totalmem() / 1024 / 1024));
  const maxCPU = Math.max(1, cpuTotal - 1);
  const maxMemoryMB = Math.max(2_048, Math.floor((memoryTotalMB / 2) / 1024) * 1024);
  const defaultCPU = Math.min(4, maxCPU);
  const defaultMemoryMB = Math.min(4_096, maxMemoryMB);

  return {
    nixPath,
    helperPath,
    capabilities: {
      supported,
      platform: process.platform,
      arch: arch(),
      helperPath,
      helperAvailable: Boolean(helperPath),
      helperEntitled,
      nixPath,
      nixAvailable: Boolean(nixPath),
      nixVersion,
      linuxBuilder,
      linuxBuilderDetail: linuxBuilderInfo,
      storageDir: options.storageDir,
      defaultChannel: DEFAULT_CHANNEL,
      defaultCPU,
      defaultMemoryMB,
      maxCPU,
      maxMemoryMB,
      notes,
    },
  };
}

export function clampCPU(value: unknown, max: number): number {
  const parsed = typeof value === "number" && Number.isFinite(value) ? Math.round(value) : 2;
  return Math.min(Math.max(parsed, 1), Math.max(1, max));
}

export function clampMemory(value: unknown, max: number): number {
  const parsed = typeof value === "number" && Number.isFinite(value) ? Math.round(value) : 4_096;
  return Math.min(Math.max(parsed, 1_024), Math.max(1_024, max));
}

export function clampDisk(value: unknown): number {
  const parsed = typeof value === "number" && Number.isFinite(value) ? Math.round(value) : 20;
  return Math.min(Math.max(parsed, 8), 512);
}

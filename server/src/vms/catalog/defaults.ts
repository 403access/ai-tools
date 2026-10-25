import type {
  NixOSBuilderConfig,
  NixOSBuilderSettings,
} from "../types.ts";
import { PRESETS } from "./presets.ts";

export const DEFAULT_SETTINGS: NixOSBuilderSettings = {
  timezone: "UTC",
  locale: "en_US.UTF-8",
  keymap: "us",
  firewall: true,
  passwordAuthentication: false,
  extraTCPPorts: [],
  extraUDPPorts: [],
};

export function defaultBuilderConfig(): NixOSBuilderConfig {
  return {
    version: 1,
    preset: null,
    enabled: [],
    settings: { ...DEFAULT_SETTINGS, extraTCPPorts: [], extraUDPPorts: [] },
    users: [],
    extraPackages: [],
    extraConfig: "",
  };
}

export function recommendedBuilderConfig(): NixOSBuilderConfig {
  const preset = PRESETS.find((entry) => entry.id === "developer") ?? PRESETS[0];
  return {
    ...defaultBuilderConfig(),
    preset: preset?.id ?? null,
    enabled: [...(preset?.options ?? ["zram"])],
  };
}

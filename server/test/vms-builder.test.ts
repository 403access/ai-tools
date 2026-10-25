import { describe, expect, test } from "bun:test";
import {
  CATEGORIES,
  OPTIONS,
  PRESETS,
  defaultBuilderConfig,
  normalizeBuilderConfig,
  resolveBuilderConfig,
} from "../src/vms/catalog/index.ts";
import { VMValidationError } from "../src/vms/errors.ts";
import { previewDraftConfiguration, renderConfiguration } from "../src/vms/nixos.ts";
import type { NixOSBuilderConfig, VirtualMachine } from "../src/vms/types.ts";

function builder(overrides: Partial<NixOSBuilderConfig> = {}): NixOSBuilderConfig {
  return { ...defaultBuilderConfig(), ...overrides };
}

describe("NixOS configuration catalog", () => {
  test("has unique ids, valid references, and categories", () => {
    const ids = new Set<string>();
    const categories = new Set(CATEGORIES.map((entry) => entry.id));
    for (const entry of OPTIONS) {
      expect(ids.has(entry.id)).toBe(false);
      ids.add(entry.id);
      expect(categories.has(entry.category)).toBe(true);
      expect(entry.name.length).toBeGreaterThan(0);
      expect(entry.summary.length).toBeGreaterThan(0);
      expect(entry.icon.length).toBeGreaterThan(0);
      for (const requirement of entry.requires) expect(ids.has(requirement) || OPTIONS.some((o) => o.id === requirement)).toBe(true);
      for (const conflict of entry.conflicts) expect(OPTIONS.some((o) => o.id === conflict)).toBe(true);
      for (const recommendation of entry.recommends) {
        expect(OPTIONS.some((o) => o.id === recommendation)).toBe(true);
      }
    }

    for (const preset of PRESETS) {
      expect(preset.options.length).toBeGreaterThan(0);
      for (const id of preset.options) {
        const entry = OPTIONS.find((option) => option.id === id);
        expect(entry).toBeDefined();
        expect(entry?.locked).toBe(false);
      }
      expect(() =>
        resolveBuilderConfig(normalizeBuilderConfig({ enabled: preset.options })),
      ).not.toThrow();
    }
  });

  test("every option snippet is structurally sound", () => {
    for (const entry of OPTIONS) {
      expect(() => {
        // The same validator the API uses for extra packages.
        const packages = entry.packages;
        for (const name of packages) {
          expect(name).toMatch(/^[A-Za-z0-9][A-Za-z0-9._+-]*$/);
        }
      }).not.toThrow();

      if (!entry.nix.trim()) continue;
      const pairs: Array<[RegExp, RegExp]> = [
        [/\{/g, /\}/g],
        [/\[/g, /\]/g],
        [/\(/g, /\)/g],
      ];
      for (const [open, close] of pairs) {
        const left = (entry.nix.match(open) ?? []).length;
        const right = (entry.nix.match(close) ?? []).length;
        expect({ id: entry.id, token: open.source, count: left }).toEqual({
          id: entry.id,
          token: open.source,
          count: right,
        });
      }
      expect(entry.nix).not.toContain("${");
      expect(entry.nix).not.toMatch(/\bundefined\b/);
    }
  });

  test("normalizes defaults, settings, users, and advanced fields", () => {
    const config = normalizeBuilderConfig({
      enabled: ["docker", "docker"],
      preset: "homelab",
      settings: {
        timezone: "Europe/Berlin",
        locale: "de_DE.UTF-8",
        keymap: "de",
        firewall: false,
        extraTCPPorts: [8080, 8080, "443"],
        extraUDPPorts: [41641],
      },
      users: [
        {
          name: "Alice",
          description: "Alice",
          groups: ["docker", "docker"],
          shell: "zsh",
          sshKeys: ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITEST alice@example"],
          passwordlessSudo: true,
        },
      ],
      extraPackages: ["ripgrep", "ripgrep"],
      extraConfig: 'environment.variables.EDITOR = "nvim";',
    });

    expect(config.enabled).toEqual(["docker"]);
    expect(config.preset).toBe("homelab");
    expect(config.settings.extraTCPPorts).toEqual([443, 8080]);
    expect(config.settings.firewall).toBe(false);
    expect(config.users[0]?.name).toBe("alice");
    expect(config.users[0]?.groups).toEqual(["docker"]);
    expect(config.users[0]?.createHome).toBe(true);
    expect(config.extraPackages).toEqual(["ripgrep"]);
  });

  test("rejects unknown options, bad users, ports, and conflicting options", () => {
    expect(() => normalizeBuilderConfig({ enabled: ["not-a-real-option"] })).toThrow(
      VMValidationError,
    );
    expect(() =>
      normalizeBuilderConfig({
        users: [{ name: "root", shell: "bash" }],
      }),
    ).toThrow(/reserved/);
    expect(() =>
      normalizeBuilderConfig({
        users: [{ name: "Alice Smith", shell: "bash" }],
      }),
    ).toThrow(/User names/);
    expect(() =>
      normalizeBuilderConfig({
        settings: { extraTCPPorts: [99999] },
      }),
    ).toThrow(/65535/);
    expect(() =>
      resolveBuilderConfig(normalizeBuilderConfig({ enabled: ["docker", "podman"] })),
    ).toThrow(/cannot be combined/);
  });

  test("expands dependencies and flattens packages, services, and ports", () => {
    const resolved = resolveBuilderConfig(
      normalizeBuilderConfig({
        enabled: ["jupyter", "postgresql", "grafana", "docker"],
      }),
    );
    expect(resolved.added).toContain("python");
    expect(resolved.config.enabled).toContain("python");
    expect(resolved.packages).toContain("python3");
    expect(resolved.packages).toContain("python3Packages.jupyterlab");
    expect(resolved.services).toContain("PostgreSQL");
    expect(resolved.services).toContain("Grafana");
    expect(resolved.ports).toContain(5432);
    expect(resolved.ports).toContain(8888);
    expect(resolved.sizeMB).toBeGreaterThan(1_024);
  });
});

describe("NixOS builder rendering", () => {
  test("renders options, users, settings, and advanced Nix", () => {
    const preview = previewDraftConfiguration({
      name: "Builder preview",
      diskGB: 40,
      config: builder({
        enabled: ["docker", "tailscale", "jupyter", "git-tools"],
        users: [
          {
            name: "alice",
            description: "Alice",
            groups: ["docker"],
            shell: "zsh",
            sshKeys: ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITEST alice@example"],
            passwordlessSudo: true,
            createHome: true,
          },
        ],
        extraPackages: ["ripgrep"],
        settings: {
          timezone: "Europe/Berlin",
          locale: "de_DE.UTF-8",
          keymap: "de",
          firewall: true,
          passwordAuthentication: false,
          extraTCPPorts: [8080],
          extraUDPPorts: [41641],
        },
        extraConfig: 'environment.variables.EDITOR = "nvim";',
      }),
    });

    expect(preview.configuration).toContain("system.stateVersion");
    expect(preview.configuration).toContain('time.timeZone = "Europe/Berlin"');
    expect(preview.configuration).toContain('console.keyMap = "de"');
    expect(preview.configuration).toContain("users.users.alice");
    expect(preview.configuration).toContain("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITEST");
    expect(preview.configuration).toContain("security.sudo.extraRules");
    expect(preview.configuration).toContain("virtualisation.docker");
    expect(preview.configuration).toContain("services.tailscale");
    expect(preview.configuration).toContain('"python3Packages" "jupyterlab"');
    expect(preview.configuration).toContain("networking.firewall.allowedTCPPorts = [ 8080 ]");
    expect(preview.configuration).toContain("networking.firewall.allowedUDPPorts = [ 41641 ]");
    expect(preview.configuration).toContain('environment.variables.EDITOR = "nvim"');
    expect(preview.configuration).not.toContain("${");
    expect(preview.packages).toContain("ripgrep");
    expect(preview.users).toEqual(["opencodebar", "alice"]);
    expect(preview.added).toContain("python");

    // Parentheses/brace balance is a cheap sanity check before Nix sees it.
    const opens = (preview.configuration.match(/\{/g) ?? []).length;
    const closes = (preview.configuration.match(/\}/g) ?? []).length;
    expect(opens).toBe(closes);
  });

  test("keeps the legacy package list and adds catalog packages", () => {
    const config = builder({ enabled: ["git-tools"], extraPackages: ["ripgrep"] });
    const vm = previewDraftConfiguration({ config }).configuration;
    expect(vm).toContain('lib.getAttrFromPath [ "git" ] pkgs');
    expect(vm).toContain('lib.getAttrFromPath [ "lazygit" ] pkgs');
    expect(vm).toContain('lib.getAttrFromPath [ "ripgrep" ] pkgs');
    expect(vm).toContain('lib.getAttrFromPath [ "curl" ] pkgs');

    const rendered = renderConfiguration(
      {
        id: "vm_abcdef123456",
        name: "Legacy",
        distro: "nixos",
        channel: "nixos-26.05",
        stateVersion: "26.05",
        arch: "aarch64",
        status: "stopped",
        createdAt: 1,
        updatedAt: 1,
        cpuCount: 2,
        memoryMB: 2_048,
        diskGB: 20,
        packages: ["nodejs"],
        pendingPackages: [],
        pendingConfig: false,
        config: defaultBuilderConfig(),
        lastError: null,
        progress: null,
        ssh: { user: "opencodebar", keyPath: "/tmp/key", publicKey: "ssh-ed25519 AAAA" },
        network: { mac: "52:54:00:00:00:00", ip: null, reachable: false },
        paths: {
          directory: "/tmp/vm",
          disk: "/tmp/vm/disk.raw",
          configuration: "/tmp/vm/configuration.nix",
          flake: "/tmp/vm/flake.nix",
          serialLog: "/tmp/vm/serial.log",
          buildLog: "/tmp/vm/build.log",
          applyLog: "/tmp/vm/apply.log",
          runtime: "/tmp/vm/runtime.json",
        },
        metrics: null,
      } satisfies VirtualMachine,
      ["nodejs"],
      config,
    );
    expect(rendered).toContain('lib.getAttrFromPath [ "nodejs" ] pkgs');
  });
});

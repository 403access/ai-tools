import XCTest
@testable import OpenCodeBar

/// Guards the VM JSON contract with `server/src/vms/types.ts`.
final class VirtualMachineTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testDecodesDefinitionAndMetrics() throws {
        let envelope = try decode(
            VirtualMachineEnvelope.self,
            """
            {
              "data": {
                "id": "vm_abcdef123456",
                "name": "NixOS dev",
                "distro": "nixos",
                "channel": "nixos-26.05",
                "stateVersion": "26.05",
                "arch": "aarch64",
                "status": "running",
                "createdAt": 1792900000000,
                "updatedAt": 1792900100000,
                "cpuCount": 4,
                "memoryMB": 4096,
                "diskGB": 20,
                "packages": ["curl", "nodejs", "ripgrep"],
                "pendingPackages": ["rustc"],
                "lastError": null,
                "progress": null,
                "ssh": {
                  "user": "opencodebar",
                  "keyPath": "/tmp/vms/vm_abcdef123456/ssh/id_ed25519",
                  "publicKey": "ssh-ed25519 AAAA test"
                },
                "network": {
                  "mac": "52:54:00:12:34:56",
                  "ip": "192.168.64.7",
                  "reachable": true
                },
                "paths": {
                  "directory": "/tmp/vms/vm_abcdef123456",
                  "disk": "/tmp/vms/vm_abcdef123456/disk.raw",
                  "configuration": "/tmp/vms/vm_abcdef123456/configuration.nix",
                  "flake": "/tmp/vms/vm_abcdef123456/flake.nix",
                  "serialLog": "/tmp/vms/vm_abcdef123456/serial.log",
                  "buildLog": "/tmp/vms/vm_abcdef123456/build.log",
                  "applyLog": "/tmp/vms/vm_abcdef123456/apply.log",
                  "runtime": "/tmp/vms/vm_abcdef123456/runtime.json"
                },
                "startedAt": 1792900050000,
                "lastBootAt": 1792900050000,
                "metrics": {
                  "collectedAt": 1792900100000,
                  "state": "running",
                  "host": {
                    "cpuPercent": 3.5,
                    "rssBytes": 52428800,
                    "diskBytes": 21474836480,
                    "diskUsedBytes": 1073741824,
                    "uptimeSec": 50
                  },
                  "guest": {
                    "reachable": true,
                    "uptimeSec": 38,
                    "cpuPercent": 12.5,
                    "load1": 0.25,
                    "load5": 0.2,
                    "load15": 0.1,
                    "memoryTotalBytes": 4294967296,
                    "memoryUsedBytes": 1073741824,
                    "memoryAvailableBytes": 3221225472,
                    "swapUsedBytes": 0,
                    "diskTotalBytes": 21474836480,
                    "diskUsedBytes": 5368709120,
                    "diskAvailableBytes": 16106127360,
                    "hostname": "ocb-abcdef123456",
                    "kernel": "6.12.0",
                    "generation": "/nix/store/abc-nixos-system-ocb-abcdef-26.05"
                  }
                }
              }
            }
            """
        )

        let vm = envelope.data
        XCTAssertEqual(vm.status, .running)
        XCTAssertTrue(vm.isRunning)
        XCTAssertTrue(vm.network.reachable)
        XCTAssertEqual(vm.extraPackages, ["nodejs", "ripgrep"])
        XCTAssertTrue(vm.hasPendingPackages)
        XCTAssertEqual(vm.sshCommand, "ssh -i /tmp/vms/vm_abcdef123456/ssh/id_ed25519 opencodebar@192.168.64.7")
        XCTAssertEqual(vm.metrics?.guest?.cpuPercent, 12.5)
        XCTAssertEqual(vm.metrics?.guest?.memoryFraction, 0.25)
        XCTAssertEqual(vm.metrics?.guest?.diskFraction, 0.25)
        XCTAssertEqual(vm.startedDate?.timeIntervalSince1970, 1792900050)
    }

    func testUnknownStatusFallsBack() throws {
        let envelope = try decode(
            VirtualMachineEnvelope.self,
            """
            {
              "data": {
                "id": "vm_abcdef123456",
                "name": "Odd",
                "distro": "nixos",
                "channel": "nixos-26.05",
                "stateVersion": "26.05",
                "arch": "aarch64",
                "status": "astral",
                "createdAt": 1,
                "updatedAt": 1,
                "cpuCount": 1,
                "memoryMB": 1024,
                "diskGB": 8,
                "packages": [],
                "pendingPackages": [],
                "ssh": { "user": "opencodebar", "keyPath": "/tmp/k", "publicKey": "ssh-ed25519 A" },
                "network": { "mac": "52:54:00:00:00:00", "ip": null, "reachable": false },
                "paths": {
                  "directory": "/tmp/v",
                  "disk": "/tmp/v/disk.raw",
                  "configuration": "/tmp/v/configuration.nix",
                  "flake": "/tmp/v/flake.nix",
                  "serialLog": "/tmp/v/serial.log",
                  "buildLog": "/tmp/v/build.log",
                  "applyLog": "/tmp/v/apply.log",
                  "runtime": "/tmp/v/runtime.json"
                }
              }
            }
            """
        )
        XCTAssertEqual(envelope.data.status, .unknown)
        XCTAssertFalse(envelope.data.isRunning)
        XCTAssertNil(envelope.data.sshCommand)
    }

    func testCapabilitiesReadiness() throws {
        let envelope = try decode(
            VMCapabilitiesEnvelope.self,
            """
            {
              "data": {
                "supported": true,
                "platform": "darwin",
                "arch": "arm64",
                "helperPath": "/tmp/OpenCodeBarVZ",
                "helperAvailable": true,
                "helperEntitled": true,
                "nixPath": "/nix/bin/nix",
                "nixAvailable": true,
                "nixVersion": "nix (Nix) 2.28.3",
                "linuxBuilder": true,
                "linuxBuilderDetail": null,
                "storageDir": "/tmp/vms",
                "defaultChannel": "nixos-26.05",
                "defaultCPU": 4,
                "defaultMemoryMB": 4096,
                "maxCPU": 7,
                "maxMemoryMB": 8192,
                "notes": []
              }
            }
            """
        )
        XCTAssertTrue(envelope.data.ready)
        XCTAssertTrue(envelope.data.notes.isEmpty)
    }

    func testDecodesLogTail() throws {
        let envelope = try decode(
            VMLogEnvelope.self,
            """
            {"data":{"type":"build","path":"/tmp/build.log","lines":["a","b"],"bytes":4,"truncated":true}}
            """
        )
        XCTAssertEqual(envelope.data.type, "build")
        XCTAssertEqual(envelope.data.lines, ["a", "b"])
        XCTAssertTrue(envelope.data.truncated)
    }

    func testDecodesBuilderConfigAndEffectiveFallback() throws {
        let envelope = try decode(
            VirtualMachineEnvelope.self,
            """
            {
              "data": {
                "id": "vm_abcdef123456",
                "name": "Builder",
                "distro": "nixos",
                "channel": "nixos-26.05",
                "stateVersion": "26.05",
                "arch": "aarch64",
                "status": "stopped",
                "createdAt": 1,
                "updatedAt": 1,
                "cpuCount": 4,
                "memoryMB": 4096,
                "diskGB": 20,
                "packages": [],
                "pendingPackages": [],
                "pendingConfig": true,
                "config": {
                  "version": 1,
                  "preset": "developer",
                  "enabled": ["docker", "tailscale"],
                  "settings": {
                    "timezone": "Europe/Berlin",
                    "locale": "en_US.UTF-8",
                    "keymap": "de",
                    "firewall": true,
                    "passwordAuthentication": false,
                    "extraTCPPorts": [8080],
                    "extraUDPPorts": []
                  },
                  "users": [
                    {
                      "name": "alice",
                      "description": "Alice",
                      "groups": ["docker"],
                      "shell": "zsh",
                      "sshKeys": [],
                      "passwordlessSudo": false,
                      "createHome": true
                    }
                  ],
                  "extraPackages": ["ripgrep"],
                  "extraConfig": ""
                },
                "lastError": null,
                "progress": null,
                "ssh": { "user": "opencodebar", "keyPath": "/tmp/k", "publicKey": "ssh-ed25519 A" },
                "network": { "mac": "52:54:00:00:00:00", "ip": null, "reachable": false },
                "paths": {
                  "directory": "/tmp/v",
                  "disk": "/tmp/v/disk.raw",
                  "configuration": "/tmp/v/configuration.nix",
                  "flake": "/tmp/v/flake.nix",
                  "serialLog": "/tmp/v/serial.log",
                  "buildLog": "/tmp/v/build.log",
                  "applyLog": "/tmp/v/apply.log",
                  "runtime": "/tmp/v/runtime.json"
                }
              }
            }
            """
        )

        let vm = envelope.data
        XCTAssertTrue(vm.hasPendingConfig)
        XCTAssertTrue(vm.hasPendingChanges)
        XCTAssertEqual(vm.builder.preset, "developer")
        XCTAssertEqual(vm.builder.enabled, ["docker", "tailscale"])
        XCTAssertEqual(vm.builder.settings.extraTCPPorts, [8080])
        XCTAssertEqual(vm.builder.users.first?.name, "alice")
        XCTAssertEqual(vm.optionCount, 2)
    }

    func testDecodesBuilderCatalog() throws {
        let envelope = try decode(
            VMConfigCatalogEnvelope.self,
            """
            {
              "data": {
                "version": 1,
                "categories": [
                  { "id": "containers", "name": "Containers", "summary": "Boxes", "icon": "shippingbox.fill", "tint": "output" }
                ],
                "options": [
                  {
                    "id": "docker",
                    "category": "containers",
                    "name": "Docker",
                    "summary": "Containers",
                    "description": "Docker Engine",
                    "icon": "shippingbox.fill",
                    "tint": "output",
                    "tags": ["Containers"],
                    "badge": "Popular",
                    "packages": [],
                    "requires": [],
                    "recommends": ["containers-tools"],
                    "conflicts": ["podman"],
                    "ports": [],
                    "services": ["Docker Engine"],
                    "defaultOn": false,
                    "locked": false,
                    "sizeMB": 380,
                    "unfree": false
                  }
                ],
                "presets": [
                  {
                    "id": "homelab",
                    "name": "Homelab",
                    "summary": "Self-hosted",
                    "icon": "server.rack",
                    "tint": "accent",
                    "options": ["docker"],
                    "tags": ["Infra"]
                  }
                ],
                "defaults": {
                  "version": 1,
                  "preset": null,
                  "enabled": [],
                  "settings": {
                    "timezone": "UTC",
                    "locale": "en_US.UTF-8",
                    "keymap": "us",
                    "firewall": true,
                    "passwordAuthentication": false,
                    "extraTCPPorts": [],
                    "extraUDPPorts": []
                  },
                  "users": [],
                  "extraPackages": [],
                  "extraConfig": ""
                },
                "recommendedPreset": "homelab",
                "shells": ["bash", "zsh", "fish"],
                "groups": ["wheel", "docker"],
                "timezones": ["UTC"],
                "locales": ["en_US.UTF-8"],
                "keymaps": ["us"],
                "limits": {
                  "maxUsers": 16,
                  "maxExtraPackages": 128,
                  "maxExtraConfigBytes": 16000,
                  "maxPorts": 32
                }
              }
            }
            """
        )

        let catalog = envelope.data
        XCTAssertEqual(catalog.options.count, 1)
        XCTAssertEqual(catalog.option("docker")?.conflicts, ["podman"])
        XCTAssertEqual(catalog.preset(catalog.recommendedPreset)?.name, "Homelab")
        XCTAssertEqual(catalog.category("containers")?.icon, "shippingbox.fill")
        XCTAssertEqual(catalog.limits.maxUsers, 16)
    }
}

@MainActor
final class NixOSBuilderModelTests: XCTestCase {
    private func option(
        _ id: String,
        category: String = "development",
        requires: [String] = [],
        conflicts: [String] = []
    ) -> VMConfigOption {
        VMConfigOption(
            id: id,
            category: category,
            name: id.capitalized,
            summary: "Summary",
            description: "Description",
            icon: "shippingbox",
            tint: "accent",
            tags: [],
            badge: nil,
            packages: [id],
            requires: requires,
            recommends: [],
            conflicts: conflicts,
            ports: [],
            services: [],
            defaultOn: false,
            locked: false,
            sizeMB: 10,
            unfree: false
        )
    }

    private func catalog() -> VMConfigCatalog {
        VMConfigCatalog(
            version: 1,
            categories: [
                VMConfigCategory(
                    id: "development",
                    name: "Development",
                    summary: "Tools",
                    icon: "hammer.fill",
                    tint: "input"
                )
            ],
            options: [
                option("python"),
                option("jupyter", requires: ["python"]),
                option("docker", category: "containers", conflicts: ["podman"]),
                option("podman", category: "containers", conflicts: ["docker"]),
            ],
            presets: [
                VMConfigPreset(
                    id: "data",
                    name: "Data",
                    summary: "Notebooks",
                    icon: "chart.xyaxis.line",
                    tint: "cacheRead",
                    options: ["jupyter"],
                    tags: ["Data"]
                )
            ],
            defaults: .fresh(),
            recommendedPreset: nil,
            shells: ["bash", "zsh", "fish"],
            groups: ["wheel", "docker"],
            timezones: ["UTC"],
            locales: ["en_US.UTF-8"],
            keymaps: ["us"],
            limits: VMConfigLimits(
                maxUsers: 16,
                maxExtraPackages: 128,
                maxExtraConfigBytes: 16_000,
                maxPorts: 32
            )
        )
    }

    func testDependenciesAndConflictsResolveLocally() {
        let model = NixOSBuilderModel(mode: .create, catalog: catalog())
        XCTAssertFalse(model.config.enabled.contains("python"))

        model.toggle(option("jupyter", requires: ["python"]))
        XCTAssertTrue(model.config.enabled.contains("jupyter"))
        XCTAssertTrue(model.config.enabled.contains("python"))
        XCTAssertTrue(model.notice?.contains("Added Python") == true)

        model.toggle(option("docker", category: "containers", conflicts: ["podman"]))
        XCTAssertTrue(model.config.enabled.contains("docker"))

        model.toggle(option("podman", category: "containers", conflicts: ["docker"]))
        XCTAssertTrue(model.config.enabled.contains("podman"))
        XCTAssertFalse(model.config.enabled.contains("docker"))

        model.toggle(option("python"))
        XCTAssertFalse(model.config.enabled.contains("python"))
        XCTAssertFalse(model.config.enabled.contains("jupyter"))
    }

    func testPresetsAndUserEditing() {
        let model = NixOSBuilderModel(mode: .create, catalog: catalog())
        let preset = model.catalog!.presets[0]
        model.applyPreset(preset)
        XCTAssertEqual(model.config.preset, "data")
        XCTAssertTrue(model.config.enabled.contains("jupyter"))
        XCTAssertTrue(model.config.enabled.contains("python"))

        model.addUser()
        XCTAssertEqual(model.config.users.count, 1)
        model.toggleGroup("docker", for: 0)
        XCTAssertEqual(model.config.users[0].groups, ["docker"])
        model.addPackages("ripgrep, fd")
        XCTAssertEqual(model.config.extraPackages, ["ripgrep", "fd"])
        model.setPorts(tcp: [8080, 8080], udp: [41641])
        XCTAssertEqual(model.config.settings.extraTCPPorts, [8080])
        XCTAssertEqual(model.config.settings.extraUDPPorts, [41641])
    }
}

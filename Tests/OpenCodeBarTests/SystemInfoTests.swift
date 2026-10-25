import XCTest
@testable import OpenCodeBar

final class SystemInfoTests: XCTestCase {
    private let json = """
    {
      "generatedAt": 1700000000000,
      "platform": "darwin",
      "platformName": "macOS",
      "host": {
        "name": "Mac",
        "hostname": "mac.local",
        "platform": "darwin",
        "platformName": "macOS",
        "osName": "macOS",
        "osVersion": "15.1",
        "osBuild": "24B83",
        "kernel": "24.1.0",
        "arch": "arm64",
        "model": "MacBook Air",
        "chip": "Apple M3",
        "machine": "Mac15,12",
        "username": "oli",
        "home": "/Users/oli",
        "shell": "/bin/zsh",
        "timezone": "Europe/Berlin",
        "locale": "en_US.UTF-8",
        "uptime": 3600,
        "bootedAt": 1699996400000,
        "isVirtualMachine": false
      },
      "hub": {
        "version": "1.0.0",
        "pid": 42,
        "runtime": "Bun",
        "runtimeVersion": "1.4.0",
        "startedAt": 1699999000000,
        "uptime": 1000,
        "port": 8787,
        "dbSizeBytes": 2048,
        "rssBytes": 4096
      },
      "cpu": {
        "model": "Apple M3",
        "vendor": "Apple",
        "architecture": "arm64",
        "physicalCores": 8,
        "logicalCores": 8,
        "usagePercent": 12.5,
        "perCoreUsage": [10, 20, 5, 15, 0, 30, 8, 12],
        "loadAverage": [1.2, 1.4, 1.1]
      },
      "memory": {
        "totalBytes": 25769803776,
        "freeBytes": 1000,
        "usedBytes": 2000,
        "availableBytes": 4000,
        "swapTotalBytes": 100,
        "swapUsedBytes": 50,
        "swapFreeBytes": 50
      },
      "disks": [
        {
          "mount": "/",
          "filesystem": "/dev/disk3s1",
          "totalBytes": 1000,
          "usedBytes": 400,
          "freeBytes": 600
        }
      ],
      "network": {
        "hostname": "mac.local",
        "interfaces": [
          {
            "name": "en0",
            "addresses": [
              {
                "address": "192.168.1.10",
                "family": "IPv4",
                "internal": false,
                "mac": "aa:bb:cc:dd:ee:ff",
                "cidr": "192.168.1.10/24"
              }
            ]
          }
        ],
        "defaultGateway": "192.168.1.1",
        "defaultInterface": "en0",
        "dnsServers": ["1.1.1.1"]
      },
      "processes": {
        "total": 1,
        "topCPU": [
          {
            "pid": 7,
            "name": "WindowServer",
            "cpuPercent": 12.5,
            "memoryBytes": 1024
          }
        ],
        "topMemory": []
      },
      "battery": null,
      "thermal": null,
      "security": {
        "systemIntegrityProtection": true,
        "fileVault": "On",
        "firewall": false,
        "gatekeeper": "enabled"
      },
      "apps": [
        {
          "name": "Xcode",
          "path": "/Applications/Xcode.app",
          "version": "16.0",
          "bundleID": "com.apple.dt.Xcode",
          "source": "apple",
          "architecture": "arm"
        }
      ],
      "homebrew": {
        "available": true,
        "version": "Homebrew 4.4.0",
        "prefix": "/opt/homebrew",
        "formulaCount": 1,
        "caskCount": 1,
        "outdatedCount": 1,
        "packages": [
          { "name": "git", "version": "2.50.0", "kind": "formula", "outdated": true },
          { "name": "raycast", "version": "1.0", "kind": "cask", "outdated": false }
        ]
      },
      "runtimes": [
        { "name": "Node.js", "version": "v24.0.0", "path": "/usr/bin/node", "kind": "runtime" }
      ],
      "displays": [
        {
          "name": "Apple M3",
          "vendor": "Apple",
          "model": "Apple M3",
          "cores": 10,
          "displays": [
            { "name": "Color LCD", "resolution": "2560 x 1664", "main": true, "online": true }
          ]
        }
      ],
      "listeningPorts": [
        {
          "port": 8787,
          "protocol": "tcp",
          "address": "*",
          "process": "bun",
          "pid": 42
        }
      ],
      "docker": {
        "available": false,
        "version": "27.0.0",
        "running": 0,
        "containers": []
      },
      "media": [
        {
          "app": "Google Chrome",
          "bundleID": "com.google.Chrome",
          "title": "Example video",
          "state": "playing",
          "elapsedSeconds": 120,
          "durationSeconds": 300,
          "playbackRate": 1,
          "kind": "video",
          "source": "mediaremote",
          "supportedCommands": [24, 3, 2, 1, 0]
        }
      ],
      "audio": {
        "volumePercent": 65,
        "muted": false,
        "controllable": true
      },
      "notes": []
    }
    """

    func testDecodesServerSnapshot() throws {
        let info = try JSONDecoder().decode(SystemInfo.self, from: Data(json.utf8))

        XCTAssertEqual(info.platformName, "macOS")
        XCTAssertEqual(info.host.uptime, 3600)
        XCTAssertEqual(info.host.bootedDate, Date(timeIntervalSince1970: 1_699_996_400))
        XCTAssertEqual(info.cpu.logicalCores, 8)
        XCTAssertEqual(info.memory.usedFraction, 2000.0 / 25769803776.0, accuracy: 0.000_001)
        XCTAssertEqual(info.disks.first?.usedFraction ?? 0, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(info.network.interfaces.first?.addresses.first?.internal_, false)
        XCTAssertEqual(info.listeningPorts.first?.protocol, "tcp")
        XCTAssertEqual(info.security?.fileVault?.isEnabled, true)
        XCTAssertEqual(info.security?.firewall?.isEnabled, false)
        XCTAssertEqual(info.homebrew?.packages.first?.outdated, true)
        XCTAssertEqual(info.apps.first?.bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(info.hub.port, 8787)
        XCTAssertEqual(info.media.first?.app, "Google Chrome")
        XCTAssertEqual(info.media.first?.isPlaying, true)
        XCTAssertEqual(info.media.first?.progress ?? 0, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(info.media.first?.kindIcon, "play.rectangle.fill")
        XCTAssertEqual(info.media.first?.supportsToggle, true)
        XCTAssertEqual(info.media.first?.supportsNext, false)
        XCTAssertEqual(info.media.first?.canControl, true)
        XCTAssertEqual(info.audio?.volumePercent, 65)
        XCTAssertEqual(info.audio?.controllable, true)
    }

    func testOptimisticMediaControlUpdates() throws {
        var info = try JSONDecoder().decode(SystemInfo.self, from: Data(json.utf8))

        let expected = MediaControlOptimism.apply(to: &info, action: "toggle", value: nil)
        XCTAssertEqual(expected, "paused")
        XCTAssertEqual(info.media.first?.isPlaying, false)
        XCTAssertEqual(info.media.first?.playbackRate, 0)

        MediaControlOptimism.reconcile(&info, expectedState: "paused")
        XCTAssertEqual(info.media.first?.state, "paused")

        MediaControlOptimism.apply(to: &info, action: "volume", value: 21)
        XCTAssertEqual(info.audio?.volumePercent, 21)

        MediaControlOptimism.apply(to: &info, action: "mute", value: 1)
        XCTAssertEqual(info.audio?.muted, true)
    }
}

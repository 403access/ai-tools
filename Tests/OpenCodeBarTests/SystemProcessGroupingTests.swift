import XCTest
@testable import OpenCodeBar

final class SystemProcessGroupingTests: XCTestCase {
    func testRollsChromeHelpersUnderApplicationBundle() throws {
        let chrome = SystemApp(
            name: "Google Chrome",
            path: "/Applications/Google Chrome.app",
            version: "131.0",
            bundleID: "com.google.Chrome",
            source: "identified_developer",
            architecture: "arm",
            lastModified: nil,
            hasIcon: true
        )
        let helperPath = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/131/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        let processes = [
            process(
                pid: 10,
                name: "Google Chrome",
                command: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                memory: 1_000
            ),
            process(
                pid: 11,
                name: "Google Chrome Helper (Renderer)",
                command: helperPath,
                memory: 2_000
            ),
            process(
                pid: 12,
                name: "Google Chrome Helper (GPU)",
                command: helperPath,
                memory: 500
            ),
        ]

        let groups = SystemProcessGrouping.groups(processes: processes, apps: [chrome])

        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.name, "Google Chrome")
        XCTAssertEqual(group.kind, .application)
        XCTAssertEqual(group.processCount, 3)
        XCTAssertEqual(group.totalMemoryBytes, 3_500)
        XCTAssertEqual(group.app?.bundleID, "com.google.Chrome")
        XCTAssertEqual(group.id, "app:/applications/google chrome.app")
    }

    func testNormalizesHelperNamesWithoutBundlePath() {
        let processes = [
            process(pid: 1, name: "Slack Helper (Renderer)", command: "/usr/local/bin/slack-helper"),
            process(pid: 2, name: "Slack Helper (GPU)", command: "/usr/local/bin/slack-helper"),
        ]

        let groups = SystemProcessGrouping.groups(processes: processes, apps: [])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "Slack")
        XCTAssertEqual(groups.first?.kind, .process)
        XCTAssertNil(groups.first?.app)
    }

    func testGroupsRepeatedExecutableNamesTogether() {
        let processes = [
            process(pid: 1, name: "node", command: "/usr/local/bin/node", memory: 200),
            process(pid: 2, name: "node", command: "/opt/homebrew/bin/node", memory: 100),
            process(pid: 3, name: "postgres", command: "/opt/homebrew/bin/postgres", memory: 400),
        ]

        let groups = SystemProcessGrouping.groups(processes: processes, apps: [])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.name, "postgres")
        XCTAssertEqual(groups.first?.totalMemoryBytes, 400)
        XCTAssertEqual(groups.last?.name, "node")
        XCTAssertEqual(groups.last?.processCount, 2)
        XCTAssertEqual(groups.last?.totalMemoryBytes, 300)
    }

    func testApplicationPathUsesOutermostBundle() {
        let helper = process(
            pid: 1,
            name: "Helper",
            command: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
        )

        XCTAssertEqual(
            SystemProcessGrouping.applicationPath(for: helper),
            "/Applications/Visual Studio Code.app"
        )
    }

    func testMergesCPUAndMemoryListsWithoutDuplicatePIDs() {
        let first = process(pid: 1, name: "first")
        let second = process(pid: 2, name: "second")
        let third = process(pid: 3, name: "third")
        let processes = SystemProcesses(
            total: 3,
            topCPU: [first, second],
            topMemory: [second, third]
        )

        XCTAssertEqual(processes.all.map(\.pid), [1, 2, 3])
    }

    func testSummaryDescribesListedProcesses() {
        let processes = [
            process(pid: 1, name: "Chrome", user: "alice", memory: 200),
            process(pid: 2, name: "Safari", user: "alice", memory: 100),
        ]
        let memory = SystemMemory(
            totalBytes: 1_000,
            freeBytes: 100,
            usedBytes: 600,
            availableBytes: 400,
            activeBytes: nil,
            inactiveBytes: nil,
            wiredBytes: nil,
            compressedBytes: nil,
            cachedBytes: nil,
            swapTotalBytes: nil,
            swapUsedBytes: nil,
            swapFreeBytes: nil
        )
        let info = makeInfo(memory: memory, processes: SystemProcesses(total: 20, topCPU: processes, topMemory: processes))
        let groups = SystemProcessGrouping.groups(for: info)
        let summary = SystemProcessSummary.make(info: info, groups: groups)

        XCTAssertEqual(summary.totalCount, 20)
        XCTAssertEqual(summary.listedCount, 2)
        XCTAssertEqual(summary.groupCount, 2)
        XCTAssertEqual(summary.listedMemoryBytes, 300)
        XCTAssertEqual(summary.outsideListBytes, 300)
        XCTAssertEqual(summary.listedFractionOfUsed, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(summary.userCount, 1)
        XCTAssertEqual(summary.topProcess?.pid, 1)
    }

    func testEstimatedPressureUsesAvailableMemory() {
        XCTAssertEqual(memory(available: 300).estimatedPressure, .normal)
        XCTAssertEqual(memory(available: 150).estimatedPressure, .elevated)
        XCTAssertEqual(memory(available: 50).estimatedPressure, .critical)
    }

    func testStateDescriptionMapsPSFlags() {
        XCTAssertEqual(process(pid: 1, name: "one", state: "S").stateDescription, "Sleeping")
        XCTAssertEqual(process(pid: 1, name: "one", state: "R+").stateDescription, "Running")
        XCTAssertEqual(process(pid: 1, name: "one", state: "T").stateDescription, "Stopped")
        XCTAssertNil(process(pid: 1, name: "one", state: "?").stateDescription)
    }

    func testDecodesExtendedProcessFields() throws {
        let json = """
        {
          "pid": 42,
          "parentPID": 1,
          "name": "Google Chrome Helper",
          "command": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper",
          "user": "oli",
          "state": "S",
          "cpuPercent": 1.5,
          "memoryPercent": 2.0,
          "memoryBytes": 1024,
          "virtualMemoryBytes": 4096,
          "elapsedSeconds": 3723
        }
        """

        let process = try JSONDecoder().decode(SystemProcess.self, from: Data(json.utf8))

        XCTAssertEqual(process.parentPID, 1)
        XCTAssertEqual(process.state, "S")
        XCTAssertEqual(process.virtualMemoryBytes, 4096)
        XCTAssertEqual(process.elapsedSeconds, 3_723)
        XCTAssertEqual(
            SystemProcessGrouping.applicationPath(for: process),
            "/Applications/Google Chrome.app"
        )
    }

    // MARK: - Fixtures

    private func process(
        pid: Int,
        name: String,
        command: String? = nil,
        user: String? = nil,
        state: String? = nil,
        memory: Int64? = nil
    ) -> SystemProcess {
        SystemProcess(
            pid: pid,
            parentPID: nil,
            name: name,
            command: command,
            user: user,
            state: state,
            cpuPercent: nil,
            memoryPercent: nil,
            memoryBytes: memory,
            virtualMemoryBytes: nil,
            elapsedSeconds: nil
        )
    }

    private func memory(available: Int64) -> SystemMemory {
        SystemMemory(
            totalBytes: 1_000,
            freeBytes: 100,
            usedBytes: 1_000 - available,
            availableBytes: available,
            activeBytes: nil,
            inactiveBytes: nil,
            wiredBytes: nil,
            compressedBytes: nil,
            cachedBytes: nil,
            swapTotalBytes: nil,
            swapUsedBytes: nil,
            swapFreeBytes: nil
        )
    }

    private func makeInfo(memory: SystemMemory, processes: SystemProcesses) -> SystemInfo {
        SystemInfo(
            generatedAt: 0,
            platform: "darwin",
            platformName: "macOS",
            host: SystemHost(
                name: "Mac",
                hostname: "mac.local",
                platform: "darwin",
                platformName: "macOS",
                osName: "macOS",
                osVersion: "15.0",
                osBuild: nil,
                kernel: "24.0.0",
                arch: "arm64",
                machine: nil,
                model: nil,
                chip: nil,
                username: nil,
                home: nil,
                shell: nil,
                timezone: nil,
                locale: nil,
                uptime: 100,
                bootedAt: nil,
                isVirtualMachine: false,
                virtualization: nil
            ),
            hub: SystemHub(
                version: "1.0",
                pid: 1,
                runtime: "Bun",
                runtimeVersion: "1.4",
                startedAt: 0,
                uptime: 100,
                port: nil,
                dbPath: nil,
                dbSizeBytes: nil,
                cwd: nil,
                execPath: nil,
                memoryBytes: nil,
                rssBytes: nil,
                heapUsedBytes: nil
            ),
            cpu: SystemCPU(
                model: nil,
                vendor: nil,
                architecture: "arm64",
                physicalCores: nil,
                logicalCores: 8,
                speedMHz: nil,
                usagePercent: nil,
                perCoreUsage: nil,
                loadAverage: nil,
                temperatureC: nil
            ),
            memory: memory,
            disks: [],
            network: SystemNetwork(
                hostname: "mac.local",
                interfaces: [],
                defaultGateway: nil,
                defaultInterface: nil,
                dnsServers: []
            ),
            processes: processes,
            battery: nil,
            thermal: nil,
            security: nil,
            apps: [],
            homebrew: nil,
            runtimes: [],
            displays: [],
            listeningPorts: [],
            docker: nil,
            media: [],
            audio: nil,
            notes: []
        )
    }
}

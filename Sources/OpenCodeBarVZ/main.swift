import Foundation

// The helper is a plain CLI: the hub spawns one instance per running guest and
// talks to it over loopback TCP. It exits when the hub sends SIGTERM after a
// stop, or when the guest is shut down and the hub reaps it.

signal(SIGPIPE, SIG_IGN)

let arguments = CommandLine.arguments
guard arguments.count == 4, arguments[1] == "run", arguments[2] == "--config" else {
    FileHandle.standardError.write(
        Data("usage: OpenCodeBarVZ run --config <path>\n".utf8)
    )
    exit(64)
}

let configPath = arguments[3]
let config: VMConfig
do {
    config = try VMConfig.load(path: configPath)
} catch {
    FileHandle.standardError.write(
        Data("could not read \(configPath): \(error.localizedDescription)\n".utf8)
    )
    exit(66)
}

let serial = SerialConsole(logPath: config.serialLog)
let runner = VMRunner(config: config, serial: serial)
let control = ControlServer(runner: runner)

do {
    try serial.start()
    try control.start()
} catch {
    FileHandle.standardError.write(
        Data("could not start helper listeners: \(error.localizedDescription)\n".utf8)
    )
    exit(70)
}

let runtime = RuntimeRecord(
    pid: getpid(),
    version: FileSupport.helperVersion,
    controlPort: control.port,
    serialPort: serial.port,
    startedAt: FileSupport.nowMillis()
)

do {
    try FileSupport.writeJSON(runtime, to: config.runtimeFile)
    try "\(getpid())\n".write(toFile: config.pidFile, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(
        Data("could not write the runtime record: \(error.localizedDescription)\n".utf8)
    )
    exit(73)
}

var signalSources: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        Task { @MainActor in
            await runner.shutdown()
            control.stop()
            FileSupport.remove(config.runtimeFile)
            FileSupport.remove(config.pidFile)
            exit(0)
        }
    }
    source.resume()
    signalSources.append(source)
}

print(
    "opencodebar-vz \(FileSupport.helperVersion) · \(config.name) · control \(control.port) · serial \(serial.port)"
)
fflush(stdout)

dispatchMain()

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenCodeBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenCodeBar", targets: ["OpenCodeBar"]),
        .executable(name: "OpenCodeBarRemoteHost", targets: ["OpenCodeBarRemoteHost"]),
        .executable(name: "OpenCodeBarVZ", targets: ["OpenCodeBarVZ"])
    ],
    dependencies: [
        // Full terminal emulation for the OpenCode PTYs shown in System. This
        // revision is after v1.5.1 removed its stray debug print and before the
        // optional Metal renderer added a .metal build resource, which needs
        // the Xcode Metal toolchain component on every build machine.
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            revision: "493d99e4e3e99a27077bf24bc0e1c8d20f9f7925"
        ),
        // On-device Parakeet speech recognition for dictation. Models run on
        // the Neural Engine and download once on first use.
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            from: "0.18.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenCodeBar",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/OpenCodeBar"
        ),
        // Screen capture and input helper for remote desktop. The hub spawns it
        // on demand; it speaks the framed protocol in Wire.swift over stdio.
        .executableTarget(
            name: "OpenCodeBarRemoteHost",
            path: "Sources/OpenCodeBarRemoteHost"
        ),
        // Virtualization.framework helper for the VMs tab. The hub spawns one
        // instance per running guest and controls it over loopback TCP.
        .executableTarget(
            name: "OpenCodeBarVZ",
            path: "Sources/OpenCodeBarVZ",
            // Used by `make vz-helper` when signing; not a SwiftPM resource.
            exclude: ["OpenCodeBarVZ.entitlements"]
        ),
        .testTarget(
            name: "OpenCodeBarTests",
            dependencies: ["OpenCodeBar"],
            path: "Tests/OpenCodeBarTests"
        )
    ]
)

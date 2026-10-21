// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenCodeBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenCodeBar", targets: ["OpenCodeBar"])
    ],
    targets: [
        .executableTarget(
            name: "OpenCodeBar",
            path: "Sources/OpenCodeBar"
        ),
        .testTarget(
            name: "OpenCodeBarTests",
            dependencies: ["OpenCodeBar"],
            path: "Tests/OpenCodeBarTests"
        )
    ]
)

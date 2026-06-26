// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iStats",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // The pure, hardware-independent core. The menu bar app target (created in
        // Xcode during Phase 1) will depend on this library.
        .library(name: "iStatsCore", targets: ["iStatsCore"])
    ],
    targets: [
        .target(
            name: "iStatsCore"
        ),
        .testTarget(
            name: "iStatsCoreTests",
            dependencies: ["iStatsCore"]
        )
    ]
)

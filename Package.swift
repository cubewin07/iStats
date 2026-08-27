// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iStats",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "iStatsCore", targets: ["iStatsCore"]),
        .library(name: "iStats", targets: ["iStats"])
    ],
    targets: [
        .target(
            name: "iStatsCore"
        ),
        .target(
            name: "iStats",
            dependencies: ["iStatsCore"],
            path: "iStats",
            exclude: ["App/iStatsApp.swift", "Resources"]
        ),
        .testTarget(
            name: "iStatsCoreTests",
            dependencies: ["iStatsCore"]
        ),
        .testTarget(
            name: "iStatsTests",
            dependencies: ["iStats", "iStatsCore"],
            path: "Tests/iStatsTests"
        )
    ]
)

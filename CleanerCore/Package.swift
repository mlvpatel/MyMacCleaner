// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CleanerCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CleanerCore",
            targets: ["CleanerCore"]
        ),
        .library(
            name: "CleanerCoreFoundation",
            targets: ["CleanerCoreFoundation"]
        ),
        .library(
            name: "CleanerCoreContentAdapter",
            targets: ["CleanerCoreContentAdapter"]
        ),
        .library(
            name: "CleanerCoreDarwin",
            targets: ["CleanerCoreDarwin"]
        )
    ],
    targets: [
        .target(name: "CleanerCore"),
        .target(
            name: "CleanerCoreFoundation",
            dependencies: ["CleanerCore"]
        ),
        .target(
            name: "CleanerCoreContentAdapter",
            dependencies: ["CleanerCore"]
        ),
        .target(
            name: "CleanerCoreDarwin",
            dependencies: ["CleanerCore"]
        ),
        .testTarget(
            name: "CleanerCoreTests",
            dependencies: ["CleanerCore", "CleanerCoreFoundation"]
        ),
        .testTarget(
            name: "CleanerCoreFoundationTests",
            dependencies: ["CleanerCore", "CleanerCoreFoundation"]
        ),
        .testTarget(
            name: "CleanerCoreContentAdapterTests",
            dependencies: ["CleanerCore", "CleanerCoreContentAdapter"]
        ),
        .testTarget(
            name: "CleanerCoreDarwinTests",
            dependencies: ["CleanerCore", "CleanerCoreDarwin"]
        )
    ]
)

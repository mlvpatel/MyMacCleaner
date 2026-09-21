// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UnsafeExtraTargetFixture",
    products: [
        .library(name: "CleanerCore", targets: ["CleanerCore"]),
        .library(name: "CleanerCoreFoundation", targets: ["CleanerCoreFoundation"]),
        .library(name: "CleanerCoreContentAdapter", targets: ["CleanerCoreContentAdapter"]),
        .library(name: "CleanerCoreDarwin", targets: ["CleanerCoreDarwin"]),
    ],
    targets: [
        .target(name: "CleanerCore"),
        .target(name: "CleanerCoreFoundation", dependencies: ["CleanerCore"]),
        .target(name: "CleanerCoreContentAdapter", dependencies: ["CleanerCore"]),
        .target(name: "CleanerCoreDarwin", dependencies: ["CleanerCore"]),
        .target(name: "Backdoor", dependencies: ["CleanerCoreContentAdapter"]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
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
        ),
    ]
)

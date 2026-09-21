// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CleanerCore",
    products: [
        .library(name: "CleanerCore", targets: ["CleanerCore"]),
        .library(name: "CleanerCoreFoundation", targets: ["CleanerCoreFoundation"]),
        .library(name: "CleanerCoreDarwin", targets: ["CleanerCoreDarwin"])
    ],
    targets: [
        .target(name: "CleanerCore"),
        .target(name: "CleanerCoreFoundation", dependencies: ["CleanerCore"]),
        .target(name: "CleanerCoreDarwin", dependencies: ["CleanerCore"]),
        .testTarget(name: "CleanerCoreDarwinTests", dependencies: ["CleanerCoreDarwin"])
    ]
)

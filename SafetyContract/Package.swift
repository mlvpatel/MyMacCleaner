// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SafetyContract",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SafetyContract",
            targets: ["SafetyContract"]
        )
    ],
    targets: [
        .target(name: "SafetyContract"),
        .testTarget(
            name: "SafetyContractTests",
            dependencies: ["SafetyContract"]
        )
    ]
)

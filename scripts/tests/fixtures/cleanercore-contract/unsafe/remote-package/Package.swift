// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UnsafeRemoteFixture",
    dependencies: [
        .package(url: "https://example.invalid/remote.git", from: "1.0.0")
    ],
    targets: []
)

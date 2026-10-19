// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SuperMenu",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SuperMenuCore", targets: ["SuperMenuCore"])
    ],
    targets: [
        .target(name: "SuperMenuCore", resources: [.process("Resources")]),
        .testTarget(name: "SuperMenuCoreTests", dependencies: ["SuperMenuCore"])
    ]
)

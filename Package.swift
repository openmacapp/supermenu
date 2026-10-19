// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SuperMenu",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SuperMenuCore", targets: ["SuperMenuCore"])
    ],
    targets: [
        .target(name: "SuperMenuCore"),
        .testTarget(name: "SuperMenuCoreTests", dependencies: ["SuperMenuCore"])
    ]
)

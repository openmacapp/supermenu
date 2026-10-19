// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SuperMenu",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SuperMenuCore", targets: ["SuperMenuCore"]),
        .library(name: "SuperMenuGit", type: .static, targets: ["SuperMenuGit"])
    ],
    dependencies: [
        .package(url: "https://github.com/craigharman/gitify.git", exact: "1.16.1")
    ],
    targets: [
        .target(name: "SuperMenuCore", resources: [.process("Resources")]),
        .testTarget(name: "SuperMenuCoreTests", dependencies: ["SuperMenuCore"]),
        .target(name: "SuperMenuGit", dependencies: [.product(name: "GitKit", package: "gitify")]),
        .testTarget(name: "SuperMenuGitTests", dependencies: ["SuperMenuGit"])
    ]
)

// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WorkBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorkBarCore", targets: ["WorkBarCore"]),
        .executable(name: "WorkBar", targets: ["WorkBar"]),
    ],
    targets: [
        .target(name: "WorkBarCore"),
        .executableTarget(name: "WorkBar", dependencies: ["WorkBarCore"]),
        .testTarget(name: "WorkBarCoreTests", dependencies: ["WorkBarCore"]),
    ])

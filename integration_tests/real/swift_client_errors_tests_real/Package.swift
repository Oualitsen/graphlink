// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GraphLinkGenerated",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "GraphLinkGenerated", targets: ["GraphLinkGenerated"]),
    ],
    targets: [
        .target(name: "GraphLinkGenerated", dependencies: []),
        .testTarget(name: "GraphLinkGeneratedTests", dependencies: ["GraphLinkGenerated"]),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GraphLinkMapperTests",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    targets: [
        .target(name: "Persistence"),
        .target(name: "GraphLinkGenerated", dependencies: ["Persistence"]),
        .testTarget(name: "MapperTests", dependencies: ["GraphLinkGenerated", "Persistence"]),
    ]
)

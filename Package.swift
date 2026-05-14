// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "inexus-osx",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NexusCore", targets: ["NexusCore"]),
        .executable(name: "nexusctl", targets: ["nexusctl"]),
        .executable(name: "NexusBar", targets: ["NexusBar"]),
    ],
    targets: [
        .target(
            name: "NexusCore",
            path: "Sources/NexusCore"
        ),
        .executableTarget(
            name: "nexusctl",
            dependencies: ["NexusCore"],
            path: "Sources/nexusctl"
        ),
        .executableTarget(
            name: "NexusBar",
            dependencies: ["NexusCore"],
            path: "Sources/NexusBar"
        ),
    ]
)

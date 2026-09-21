// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SimpleLaunchpad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SimpleLaunchpad",
            path: "Sources/SimpleLaunchpad",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns", "Resources/AppIcon.svg"]
        ),
        .testTarget(
            name: "SimpleLaunchpadTests",
            dependencies: ["SimpleLaunchpad"],
            path: "Tests/SimpleLaunchpadTests"
        )
    ]
)

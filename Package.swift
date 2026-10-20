// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowThere",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BrowThere",
            path: "Sources/BrowThere",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        ),
        .testTarget(name: "BrowThereTests", dependencies: ["BrowThere"]),
    ]
)

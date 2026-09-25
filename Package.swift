// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "Ledge", dependencies: ["NotchKit", "ActivityKit", "PowerService", "HUDService", "MediaService"], path: "Sources/Ledge"),
        .target(name: "NotchKit"),
        .target(name: "ActivityKit"),
        .target(name: "PowerService", dependencies: ["ActivityKit"]),
        .target(name: "HUDService", dependencies: ["ActivityKit"]),
        .target(name: "MediaService", dependencies: ["ActivityKit"]),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"]),
        .testTarget(name: "NotchWindowTests", dependencies: ["NotchKit"]),
        .testTarget(name: "NotchRenderTests", dependencies: ["NotchKit"]),
        .testTarget(name: "ActivityKitTests", dependencies: ["ActivityKit"]),
        .testTarget(name: "PowerServiceTests", dependencies: ["PowerService"]),
        .testTarget(name: "HUDServiceTests", dependencies: ["HUDService"]),
        .testTarget(
            name: "MediaServiceTests",
            dependencies: ["MediaService"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

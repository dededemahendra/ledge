// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "Ledge", dependencies: ["NotchKit", "ActivityKit", "PowerService"], path: "Sources/Ledge"),
        .target(name: "NotchKit"),
        .target(name: "ActivityKit"),
        .target(name: "PowerService", dependencies: ["ActivityKit"]),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"]),
        .testTarget(name: "NotchWindowTests", dependencies: ["NotchKit"]),
        .testTarget(name: "ActivityKitTests", dependencies: ["ActivityKit"]),
        .testTarget(name: "PowerServiceTests", dependencies: ["PowerService"]),
    ],
    swiftLanguageModes: [.v6]
)

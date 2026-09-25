// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "Ledge", dependencies: ["NotchKit"], path: "Sources/Ledge"),
        .target(name: "NotchKit"),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"]),
        .testTarget(name: "NotchWindowTests", dependencies: ["NotchKit"]),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "Ledge", dependencies: ["NotchKit", "ActivityKit", "PowerService", "HUDService", "MediaService", "DeviceService", "CalendarService", "TimerService", "FocusService", "LiveActivityService", "LedgeSettings", "SettingsKit", "UpdateService", "GitHubService", "CallService"], path: "Sources/Ledge"),
        .target(name: "NotchKit"),
        .target(name: "ActivityKit"),
        .target(name: "PowerService", dependencies: ["ActivityKit"]),
        .target(name: "HUDService", dependencies: ["ActivityKit"]),
        .target(name: "MediaService", dependencies: ["ActivityKit"]),
        .target(name: "DeviceService", dependencies: ["ActivityKit"]),
        .target(name: "CalendarService", dependencies: ["ActivityKit"]),
        .target(name: "TimerService"),
        .target(name: "FocusService", dependencies: ["ActivityKit"]),
        .target(name: "LiveActivityService", dependencies: ["ActivityKit"]),
        .target(name: "LedgeSettings"),
        .target(name: "UpdateService"),
        .target(name: "GitHubService"),
        .target(name: "CallService", dependencies: ["ActivityKit"]),
        .target(name: "SettingsKit", dependencies: ["NotchKit", "LedgeSettings", "HUDService", "PowerService", "DeviceService", "FocusService", "UpdateService", "GitHubService"]),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"]),
        .testTarget(name: "NotchWindowTests", dependencies: ["NotchKit"]),
        .testTarget(name: "NotchRenderTests", dependencies: ["NotchKit"]),
        .testTarget(name: "ActivityKitTests", dependencies: ["ActivityKit"]),
        .testTarget(name: "PowerServiceTests", dependencies: ["PowerService"]),
        .testTarget(name: "HUDServiceTests", dependencies: ["HUDService"]),
        .testTarget(name: "DeviceServiceTests", dependencies: ["DeviceService"]),
        .testTarget(name: "CalendarServiceTests", dependencies: ["CalendarService"]),
        .testTarget(name: "TimerServiceTests", dependencies: ["TimerService"]),
        .testTarget(name: "FocusServiceTests", dependencies: ["FocusService"]),
        .testTarget(name: "LiveActivityServiceTests", dependencies: ["LiveActivityService"]),
        .testTarget(name: "LedgeSettingsTests", dependencies: ["LedgeSettings"]),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit", "NotchKit", "LedgeSettings", "HUDService", "GitHubService"]),
        .testTarget(name: "UpdateServiceTests", dependencies: ["UpdateService"]),
        .testTarget(name: "GitHubServiceTests", dependencies: ["GitHubService"]),
        .testTarget(name: "CallServiceTests", dependencies: ["CallService"]),
        .testTarget(
            name: "MediaServiceTests",
            dependencies: ["MediaService"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

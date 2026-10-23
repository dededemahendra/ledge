import AppKit
import Foundation
import NotchKit
import GitHubService

/// The user's own content for the Settings previews (2026-10-22), every
/// field optional: `AppModel.previewContent()` fills what the island
/// already knows, and a strip shows a labelled sample for the rest.
public struct PreviewContent: Sendable, Equatable {
    /// The headphones in use and the charge they report.
    public struct Headphones: Sendable, Equatable {
        public let name: String
        public let main: Int?
        public let left: Int?
        public let right: Int?
        public let `case`: Int?

        public init(name: String, main: Int? = nil, left: Int? = nil, right: Int? = nil, case: Int? = nil) {
            self.name = name
            self.main = main
            self.left = left
            self.right = right
            self.case = `case`
        }
    }

    /// The last Focus that came on.
    public struct Focus: Sendable, Equatable {
        public let name: String
        public let symbolName: String?
        public let tintName: String?

        public init(name: String, symbolName: String?, tintName: String?) {
            self.name = name
            self.symbolName = symbolName
            self.tintName = tintName
        }
    }

    public var media: MediaPresentation?
    /// The bundle identifier of the app playing `media`.
    public var mediaSource: String?
    public var nextEvent: UpcomingEvent?
    public var nextReminder: UpcomingEvent?
    public var batteryPercent: Int?
    public var headphones: Headphones?
    public var focus: Focus?
    /// The last volume level seen, `0...1`.
    public var volume: Double?
    /// A Clock timer running now, as the island shows it.
    public var timer: NotchController.ActivityDisplay?
    /// A newer version that is really out, for the update scene.
    public var availableUpdate: String?
    /// The user's latest open PR, for the GitHub scenes (2026-10-22).
    public var pullRequest: GitHubPR?

    public init(
        media: MediaPresentation? = nil, mediaSource: String? = nil,
        nextEvent: UpcomingEvent? = nil, nextReminder: UpcomingEvent? = nil,
        batteryPercent: Int? = nil, headphones: Headphones? = nil, focus: Focus? = nil,
        volume: Double? = nil, timer: NotchController.ActivityDisplay? = nil,
        availableUpdate: String? = nil, pullRequest: GitHubPR? = nil
    ) {
        self.media = media
        self.mediaSource = mediaSource
        self.nextEvent = nextEvent
        self.nextReminder = nextReminder
        self.batteryPercent = batteryPercent
        self.headphones = headphones
        self.focus = focus
        self.volume = volume
        self.timer = timer
        self.availableUpdate = availableUpdate
        self.pullRequest = pullRequest
    }
}

/// What a strip shows where the user has nothing of their own.
public enum PreviewSample {
    public static let media = MediaPresentation(
        title: "Night Drive", artist: "The Islands", artwork: nil,
        isPlaying: true, elapsed: 74, duration: 243, anchor: Date(timeIntervalSinceReferenceDate: 0)
    )
    public static let volume = 0.62
    public static let updateVersion = "0.1.2"
    public static let brightness = 0.7
    public static let batteryPercent = 87
    public static let headphones = PreviewContent.Headphones(name: "AirPods Pro", left: 80, right: 80, case: 60)
    public static let focus = PreviewContent.Focus(name: "Do Not Disturb", symbolName: "moon.fill", tintName: "indigo")
    public static let event = UpcomingEvent(
        title: "Design review", symbolName: "calendar", compactText: "5m",
        caption: "Design review · 14:00", time: "14:00", url: nil, kind: .event
    )
    public static let reminder = UpcomingEvent(
        title: "Call the plumber", symbolName: "circle", compactText: "5m",
        caption: "Call the plumber · 17:30", time: "17:30", url: nil,
        tint: .init(red: 1, green: 0.58, blue: 0), kind: .reminder
    )
    @MainActor public static let timer = NotchController.ActivityDisplay(
        id: NotchController.timerActivityID, title: "Timer", compactText: "4:32",
        symbolName: "stopwatch", barFill: 0.6, tint: .system("orange")
    )
    /// A call (2026-10-22): FaceTime's own icon when it can be found, else
    /// the green mic, at "12:04".
    @MainActor public static let call = NotchController.ActivityDisplay(
        id: NotchController.callActivityID, title: "On a call · FaceTime", compactText: "12:04",
        symbolName: "mic.fill", artwork: facetimeIcon(), tint: .positive
    )
    @MainActor private static func facetimeIcon() -> Data? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FaceTime") else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
    }
    /// A finished command (2026-10-23): a green check, its time, and the
    /// caption the island shows with it.
    @MainActor public static let longCommand = NotchController.ActivityDisplay(
        id: NotchController.commandActivityID, title: "make test", compactText: "1:20",
        symbolName: "checkmark.circle.fill", tint: .positive
    )
    public static let longCommandCaption = "make test · 1m 20s"
    @MainActor public static let liveActivity = NotchController.ActivityDisplay(
        id: NotchController.liveActivityID, title: "Live Activity",
        score: .init(home: .init(name: "HOME", value: "2", crest: nil),
                     away: .init(name: "AWAY", value: "1", crest: nil),
                     status: "2H", clock: "67'")
    )
}

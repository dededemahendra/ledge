import Foundation

/// What the call card shows (2026-10-22). Built by `AppModel` from
/// CallService; pure here, so NotchKit stays free of the service.
public struct CallPanelData: Sendable, Equatable {
    public let appName: String
    /// The app's icon as PNG.
    public let icon: Data?
    /// When the mic was first taken; the card's clock counts from here.
    public let since: Date
    public let isMuted: Bool
    /// Whether any running mic can be muted from Ledge at all.
    public let canMute: Bool
    /// The running mic's name, "2 mics" when several run.
    public let micName: String?
    /// The calendar meeting this call is (2026-10-22): its title in place of
    /// the app's name, and its end for the time left.
    public let meetingTitle: String?
    public let meetingEnd: Date?
    public let isCameraOn: Bool
    /// The next meeting within ten minutes, as "1:1 at 15:00".
    public let nextMeeting: String?

    public init(appName: String, icon: Data?, since: Date, isMuted: Bool, canMute: Bool, micName: String?,
                meetingTitle: String? = nil, meetingEnd: Date? = nil, isCameraOn: Bool = false, nextMeeting: String? = nil) {
        self.appName = appName
        self.icon = icon
        self.since = since
        self.isMuted = isMuted
        self.canMute = canMute
        self.micName = micName
        self.meetingTitle = meetingTitle
        self.meetingEnd = meetingEnd
        self.isCameraOn = isCameraOn
        self.nextMeeting = nextMeeting
    }
}

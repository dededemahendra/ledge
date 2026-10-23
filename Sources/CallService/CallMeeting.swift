import Foundation

/// The meeting services a call can be recognised as (2026-10-22).
public enum MeetingService: String, Sendable, Equatable, CaseIterable {
    case meet, zoom, teams, webex, facetime
}

/// A calendar event as the matcher sees it. Plain values, so CallService
/// stays free of EventKit; `AppModel` maps `MeetingEvent`s to these. An
/// event without a link never matches a call but can still be "next".
public struct MeetingCandidate: Sendable, Equatable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let joinURL: URL?

    public init(id: String, title: String, start: Date, end: Date, joinURL: URL?) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.joinURL = joinURL
    }
}

/// The meeting a call is.
public struct CallMeeting: Sendable, Equatable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let joinURL: URL
    public let service: MeetingService

    public init(id: String, title: String, start: Date, end: Date, joinURL: URL, service: MeetingService) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.joinURL = joinURL
        self.service = service
    }
}

/// Which calendar meeting a call is (2026-10-22): an event with a Meet,
/// Zoom, Teams, Webex or FaceTime link, from ten minutes before its start
/// until its end, held by an app that service runs in — its own app, or a
/// browser. The nearest start wins. A browser can't say which site a tab
/// is on, so a browser call during a meeting's window is that meeting.
public enum CallMeetingMatcher {
    /// How early a call may be the meeting, and how soon "next" looks.
    public static let lead: TimeInterval = 600
    public static let nextWithin: TimeInterval = 600

    public static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.Browser", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "com.kagi.kagimacOS",
    ]

    /// Each service's own Mac apps, beyond the browsers.
    public static let apps: [MeetingService: [String]] = [
        .meet: [],
        .zoom: ["us.zoom.xos"],
        .teams: ["com.microsoft.teams2", "com.microsoft.teams"],
        .webex: ["Cisco-Systems.Spark", "com.webex.meetingmanager"],
        .facetime: ["com.apple.FaceTime"],
    ]

    private static let hosts: [(host: String, service: MeetingService)] = [
        ("meet.google.com", .meet), ("zoom.us", .zoom), ("teams.microsoft.com", .teams), ("teams.live.com", .teams),
        ("webex.com", .webex), ("facetime.apple.com", .facetime),
    ]

    public static func service(for url: URL) -> MeetingService? {
        guard let host = url.host()?.lowercased() else { return nil }
        return hosts.first { host == $0.host || host.hasSuffix("." + $0.host) }?.service
    }

    public static func accepts(_ service: MeetingService, bundleID: String) -> Bool {
        browsers.contains(bundleID) || (apps[service] ?? []).contains(bundleID)
    }

    /// `requireUnderWay`: for a hidden app, only a meeting that has begun.
    public static func match(bundleID: String, at now: Date, in candidates: [MeetingCandidate],
                             requireUnderWay: Bool = false) -> CallMeeting? {
        let opens = requireUnderWay ? 0 : lead
        return candidates
            .compactMap { candidate -> CallMeeting? in
                guard let url = candidate.joinURL, let service = service(for: url),
                      accepts(service, bundleID: bundleID),
                      candidate.start.addingTimeInterval(-opens) <= now, now < candidate.end else { return nil }
                return CallMeeting(id: candidate.id, title: candidate.title, start: candidate.start, end: candidate.end,
                                   joinURL: url, service: service)
            }
            .min { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
    }

    /// The next event to start within `nextWithin`, other than the call's
    /// own meeting — nor a copy of it in another calendar (a shared team
    /// calendar), which has its own id but the same start and link or title.
    public static func next(after now: Date, in candidates: [MeetingCandidate], excluding meeting: CallMeeting?) -> MeetingCandidate? {
        candidates
            .filter { candidate in
                guard let meeting else { return true }
                let isCopy = candidate.start == meeting.start
                    && (candidate.joinURL == meeting.joinURL || candidate.title == meeting.title)
                return candidate.id != meeting.id && !isCopy
            }
            .filter { $0.start > now && $0.start.timeIntervalSince(now) <= nextWithin }
            .min { $0.start < $1.start }
    }
}

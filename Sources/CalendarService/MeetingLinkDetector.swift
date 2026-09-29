import Foundation

/// Finds the video-call link in an event: its URL field first, then the
/// location, then the notes — the three places invitations put it. Only
/// known meeting hosts count; an agenda link in the notes is not a call.
public enum MeetingLinkDetector {
    public static let meetingHosts: [String] = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "facetime.apple.com", "whereby.com", "around.co",
        "meet.jit.si", "gotomeeting.com", "bluejeans.com", "discord.gg",
    ]

    public static func joinURL(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isMeetingHost(url) { return url }
        for text in [location, notes].compactMap({ $0 }) {
            if let found = firstMeetingLink(in: text) { return found }
        }
        return nil
    }

    static func isMeetingHost(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func firstMeetingLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, isMeetingHost(url) { return url }
        }
        return nil
    }
}

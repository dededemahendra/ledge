import Foundation
import Testing
@testable import CallService

private let t0 = Date(timeIntervalSince1970: 100_000)

/// A calendar event `start` to `end` minutes from `t0`.
private func event(_ id: String, start: Double, end: Double, url: String? = "https://meet.google.com/abc-defg-hij",
                   title: String = "Design review") -> MeetingCandidate {
    MeetingCandidate(id: id, title: title, start: t0.addingTimeInterval(start * 60), end: t0.addingTimeInterval(end * 60),
                     joinURL: url.flatMap(URL.init(string:)))
}

@Test func meetInABrowserMatches() {
    let match = CallMeetingMatcher.match(bundleID: "company.thebrowser.dia", at: t0, in: [event("m", start: 0, end: 30)])
    #expect(match?.service == .meet)
    #expect(match?.title == "Design review")
    #expect(match?.id == "m")
}

@Test func meetInZoomsAppDoesNot() {
    #expect(CallMeetingMatcher.match(bundleID: "us.zoom.xos", at: t0, in: [event("m", start: 0, end: 30)]) == nil)
}

@Test func zoomMatchesInItsAppAndInABrowser() {
    let zoom = [event("z", start: 0, end: 30, url: "https://us02web.zoom.us/j/123")]
    #expect(CallMeetingMatcher.match(bundleID: "us.zoom.xos", at: t0, in: zoom)?.service == .zoom)
    #expect(CallMeetingMatcher.match(bundleID: "com.google.Chrome", at: t0, in: zoom)?.service == .zoom)
}

@Test func teamsMatchesInEitherTeamsApp() {
    let teams = [event("t", start: 0, end: 30, url: "https://teams.microsoft.com/l/meetup-join/x")]
    #expect(CallMeetingMatcher.match(bundleID: "com.microsoft.teams2", at: t0, in: teams)?.service == .teams)
    #expect(CallMeetingMatcher.match(bundleID: "com.microsoft.teams", at: t0, in: teams)?.service == .teams)
}

@Test func theWindowOpensTenMinutesBefore() {
    #expect(CallMeetingMatcher.match(bundleID: "com.apple.Safari", at: t0, in: [event("m", start: 11, end: 40)]) == nil)
    #expect(CallMeetingMatcher.match(bundleID: "com.apple.Safari", at: t0, in: [event("m", start: 10, end: 40)]) != nil)
}

@Test func aCallStartingAtTheEndDoesNotMatch() {
    #expect(CallMeetingMatcher.match(bundleID: "com.apple.Safari", at: t0, in: [event("m", start: -30, end: 0)]) == nil)
}

@Test func theNearestStartWins() {
    let match = CallMeetingMatcher.match(bundleID: "com.apple.Safari", at: t0,
                                         in: [event("a", start: -50, end: 5), event("b", start: 2, end: 30)])
    #expect(match?.id == "b")
}

@Test func noLinkOrAnotherServiceNeverMatches() {
    #expect(CallMeetingMatcher.match(bundleID: "com.apple.Safari", at: t0, in: [event("n", start: 0, end: 30, url: nil)]) == nil)
    #expect(CallMeetingMatcher.match(bundleID: "com.apple.Safari", at: t0,
                                     in: [event("w", start: 0, end: 30, url: "https://whereby.com/room")]) == nil)
}

/// A hidden app is shown as a meeting only once the meeting is under way.
@Test func aHiddenAppNeedsTheMeetingUnderWay() {
    #expect(CallMeetingMatcher.match(bundleID: "com.apple.Safari", at: t0, in: [event("m", start: 5, end: 30)],
                                     requireUnderWay: true) == nil)
    #expect(CallMeetingMatcher.match(bundleID: "com.apple.Safari", at: t0, in: [event("m", start: -1, end: 30)],
                                     requireUnderWay: true) != nil)
}

@Test func nextIsWithinTenMinutesAndNeverTheMatchedOne() {
    #expect(CallMeetingMatcher.next(after: t0, in: [event("b", start: 9, end: 30)], excluding: nil)?.id == "b")
    #expect(CallMeetingMatcher.next(after: t0, in: [event("b", start: 11, end: 30)], excluding: nil) == nil)
    let b = event("b", start: 9, end: 30)
    let matchedB = CallMeeting(id: b.id, title: b.title, start: b.start, end: b.end, joinURL: b.joinURL!, service: .meet)
    #expect(CallMeetingMatcher.next(after: t0, in: [b], excluding: matchedB) == nil)
    #expect(CallMeetingMatcher.next(after: t0, in: [event("c", start: 5, end: 30, url: nil)], excluding: nil)?.id == "c",
            "an event without a link still counts as next")
}

/// The same meeting in two calendars (a shared team calendar) has two ids;
/// the copy is not "next" (tidy-up, 2026-10-22).
@Test func aMeetingCopiedInAnotherCalendarIsNotItsOwnNext() {
    let mine = event("m", start: 5, end: 35)
    let matched = CallMeeting(id: mine.id, title: mine.title, start: mine.start, end: mine.end, joinURL: mine.joinURL!,
                              service: .meet)
    let copy = event("m-team-calendar", start: 5, end: 35)
    #expect(CallMeetingMatcher.next(after: t0, in: [mine, copy], excluding: matched) == nil)
}

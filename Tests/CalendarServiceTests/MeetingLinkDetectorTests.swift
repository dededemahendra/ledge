import Testing
import Foundation
@testable import CalendarService

@Test func theURLFieldWinsWhenItIsACall() {
    let zoom = URL(string: "https://us02web.zoom.us/j/123456789?pwd=abc")!
    #expect(MeetingLinkDetector.joinURL(url: zoom, location: "https://meet.google.com/abc-defg-hij", notes: nil) == zoom)
}

@Test func locationAndNotesAreSearchedInThatOrder() {
    let meet = URL(string: "https://meet.google.com/abc-defg-hij")!
    #expect(MeetingLinkDetector.joinURL(url: nil, location: "Room 4 — https://meet.google.com/abc-defg-hij", notes: "https://zoom.us/j/1") == meet)
    let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d"
    #expect(MeetingLinkDetector.joinURL(url: nil, location: "Building B", notes: "Join here: \(teams)\nAgenda: https://example.com/agenda")?.absoluteString == teams)
}

@Test func linksThatAreNotCallsDoNotCount() {
    #expect(MeetingLinkDetector.joinURL(url: URL(string: "https://example.com/agenda"), location: "Café", notes: "See https://docs.example.com/plan") == nil)
    #expect(MeetingLinkDetector.joinURL(url: nil, location: nil, notes: nil) == nil)
    #expect(MeetingLinkDetector.joinURL(url: URL(string: "https://notzoom.us/j/1"), location: nil, notes: nil) == nil,
            "a host must match exactly or as a subdomain, not by suffix of a longer name")
}

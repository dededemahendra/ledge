import AppKit
import Testing
@testable import NotchKit

private let now = Date(timeIntervalSince1970: 100_000)

@Test func timeLeftInMinutesThenHours() {
    #expect(CallMeetingText.timeLeft(end: now.addingTimeInterval(12 * 60 + 30), now: now) == ("12m left", false))
    #expect(CallMeetingText.timeLeft(end: now.addingTimeInterval(65 * 60), now: now) == ("1h 5m left", false))
    #expect(CallMeetingText.timeLeft(end: now.addingTimeInterval(60 * 60), now: now) == ("1h left", false))
}

@Test func underAMinuteIsEndingNow() {
    #expect(CallMeetingText.timeLeft(end: now.addingTimeInterval(30), now: now) == ("Ending now", false))
}

@Test func overIsAPlusInRed() {
    #expect(CallMeetingText.timeLeft(end: now.addingTimeInterval(-3 * 60), now: now) == ("+3m", true))
    #expect(CallMeetingText.timeLeft(end: now.addingTimeInterval(-62 * 60), now: now) == ("+1h 2m", true))
    #expect(CallMeetingText.timeLeft(end: now.addingTimeInterval(-10), now: now) == ("+1m", true))
}

@MainActor
@Test func aTileIsASquarePNG() throws {
    let png = try #require(CallTile.png(symbol: "video.fill", color: .systemGreen))
    let rep = try #require(NSBitmapImageRep(data: png))
    #expect(rep.pixelsWide == 64 && rep.pixelsHigh == 64)
}

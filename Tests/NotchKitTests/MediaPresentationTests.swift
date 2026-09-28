import Testing
import Foundation
@testable import NotchKit

private func presentation(elapsed: Double, duration: Double?) -> MediaPresentation {
    MediaPresentation(
        title: "Song", artist: "Artist", artwork: nil,
        isPlaying: true, elapsed: elapsed, duration: duration
    )
}

@Test func progressIsTheFractionPlayed() {
    #expect(presentation(elapsed: 105, duration: 210).progress == 0.5)
    #expect(presentation(elapsed: 0, duration: 210).progress == 0)
    #expect(presentation(elapsed: 210, duration: 210).progress == 1)
}

@Test func progressIsZeroWhenDurationIsUnknownOrZero() {
    #expect(presentation(elapsed: 50, duration: nil).progress == 0,
            "a live stream must not render a meaningless full bar")
    #expect(presentation(elapsed: 50, duration: 0).progress == 0)
}

@Test func progressIsClampedToUnitRange() {
    #expect(presentation(elapsed: 500, duration: 210).progress == 1)
    #expect(presentation(elapsed: -20, duration: 210).progress == 0)
}

@Test func timesFormatAsMinutesAndSeconds() {
    #expect(presentation(elapsed: 0, duration: 210).elapsedText == "0:00")
    #expect(presentation(elapsed: 9, duration: 210).elapsedText == "0:09")
    #expect(presentation(elapsed: 65, duration: 210).elapsedText == "1:05")
    #expect(presentation(elapsed: 3661, duration: 7200).elapsedText == "1:01:01", "an hour reads as a clock, not as 61 minutes")
    #expect(presentation(elapsed: 3599, duration: 7200).elapsedText == "59:59")
    #expect(presentation(elapsed: 192, duration: 2304).elapsedText == "3:12")
    #expect(presentation(elapsed: 192, duration: 2304).remainingText == "-35:12", "the 38-minute video from the report")
    #expect(presentation(elapsed: 60, duration: 4320).remainingText == "-1:11:00")
}

@Test func remainingTimeIsNegativeAndAbsentWithoutDuration() {
    #expect(presentation(elapsed: 105, duration: 210).remainingText == "-1:45")
    #expect(presentation(elapsed: 210, duration: 210).remainingText == "-0:00")
    #expect(presentation(elapsed: 50, duration: nil).remainingText == nil)
}

@Test func seekIntentCarriesAFractionNotSeconds() {
    // The view knows the bar's width; only the model knows the duration.
    #expect(NotchIntent.seek(fraction: 0.5) == .seek(fraction: 0.5))
}

@MainActor
@Test func settingMediaMakesTheIslandTreatItAsAStickyActivity() {
    let controller = NotchController(
        metrics: NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32))
    )
    #expect(controller.media == nil)
    controller.setMedia(presentation(elapsed: 10, duration: 210))
    #expect(controller.media?.title == "Song")
    controller.setMedia(nil)
    #expect(controller.media == nil)
}

@MainActor
@Test func intentsAreForwardedToTheHandler() {
    let controller = NotchController(
        metrics: NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32))
    )
    var received: [NotchIntent] = []
    controller.onIntent = { received.append($0) }
    controller.emit(.togglePlayPause)
    controller.emit(.seek(fraction: 0.25))
    #expect(received == [.togglePlayPause, .seek(fraction: 0.25)])
}

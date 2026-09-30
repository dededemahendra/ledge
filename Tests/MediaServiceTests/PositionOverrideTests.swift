import Testing
import Foundation
@testable import MediaService

private let t0 = Date(timeIntervalSinceReferenceDate: 820_000_000)

@Test func anOverrideLastsTwoSecondsUnlessThePlayerReportsSomethingNewer() {
    let override = PositionOverride(elapsedTime: 42, timestamp: t0, playing: false)
    #expect(override.isFresh(at: t0 + 1.9))
    #expect(!override.isFresh(at: t0 + 2))

    var stale = MediaPayload()
    stale.timestamp = t0 - 5
    #expect(!override.isSuperseded(by: stale), "an unrelated report from before the action must not snap the card back")
    var confirmation = MediaPayload()
    confirmation.timestamp = t0 + 0.2
    #expect(override.isSuperseded(by: confirmation))
    #expect(!override.isSuperseded(by: MediaPayload()), "no timestamp: not a position report")
}

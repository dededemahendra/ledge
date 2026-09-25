import Testing
import Foundation
@testable import MediaService

private let t0 = Date(timeIntervalSince1970: 1_790_308_800)

@Test func positionAdvancesWithWallClockWhilePlaying() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(10), elapsedTime: 30, timestamp: t0, rate: 1, duration: 210
    )
    #expect(p == 40)
}

@Test func positionIsFrozenWhenPaused() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(60), elapsedTime: 30, timestamp: t0, rate: 0, duration: 210
    )
    #expect(p == 30)
}

@Test func positionRespectsPlaybackRate() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(10), elapsedTime: 0, timestamp: t0, rate: 1.5, duration: 210
    )
    #expect(p == 15)
}

@Test func positionNeverExceedsDuration() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(9999), elapsedTime: 200, timestamp: t0, rate: 1, duration: 210
    )
    #expect(p == 210, "a scrubber past the end looks broken")
}

@Test func positionNeverGoesNegative() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(-50), elapsedTime: 10, timestamp: t0, rate: 1, duration: 210
    )
    #expect(p == 0, "clock skew must not produce a negative position")
}

@Test func unknownDurationStillExtrapolates() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(10), elapsedTime: 5, timestamp: t0, rate: 1, duration: nil
    )
    #expect(p == 15)
}

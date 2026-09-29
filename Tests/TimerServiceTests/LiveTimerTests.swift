import Testing
import Foundation
@testable import TimerService

private let t0 = Date(timeIntervalSinceReferenceDate: 900_000_000)

@Test func aCountdownCountsDownRoundingUpAndFinishes() {
    let timer = LiveTimer(kind: .countdown(300), at: t0)
    #expect(timer.displayText(at: t0) == "5:00")
    #expect(timer.displayText(at: t0 + 0.4) == "5:00", "rounds up: the first second still shows whole")
    #expect(timer.displayText(at: t0 + 1) == "4:59")
    #expect(timer.displayText(at: t0 + 295.8) == "0:05")
    #expect(timer.fraction(at: t0 + 150) == 0.5)
    #expect(!timer.isFinished(at: t0 + 299.9))
    #expect(timer.isFinished(at: t0 + 300))
    #expect(timer.displayText(at: t0 + 301) == "0:00")
    #expect(timer.remaining(at: t0 + 400) == 0, "never negative")
}

@Test func pauseBanksTimeAndResumeContinuesFromThere() {
    var timer = LiveTimer(kind: .countdown(60), at: t0)
    timer.pause(at: t0 + 10)
    #expect(timer.isPaused)
    #expect(timer.displayText(at: t0 + 40) == "0:50", "frozen while paused")
    timer.resume(at: t0 + 40)
    #expect(!timer.isPaused)
    #expect(timer.displayText(at: t0 + 45) == "0:45")
    timer.togglePause(at: t0 + 45)
    #expect(timer.isPaused)
    timer.togglePause(at: t0 + 100)
    #expect(timer.displayText(at: t0 + 100) == "0:45", "a toggle pair costs nothing")
}

@Test func aStopwatchCountsUpAndNeverFinishes() {
    let watch = LiveTimer(kind: .stopwatch, at: t0)
    #expect(watch.isStopwatch)
    #expect(watch.displayText(at: t0 + 754.9) == "12:34", "rounds down")
    #expect(watch.fraction(at: t0 + 10) == nil, "no ring without an end")
    #expect(!watch.isFinished(at: t0 + 100_000))
}

@Test func formatFitsTheEar() {
    #expect(LiveTimer.format(seconds: 5) == "0:05")
    #expect(LiveTimer.format(seconds: 754) == "12:34")
    #expect(LiveTimer.format(seconds: 3599) == "59:59")
    #expect(LiveTimer.format(seconds: 3720) == "1:02", "hours:minutes from an hour up")
    #expect(LiveTimer.format(seconds: -3) == "0:00")
}

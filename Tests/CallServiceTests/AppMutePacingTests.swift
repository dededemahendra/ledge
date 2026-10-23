import Foundation
import Testing
@testable import CallService

private let t0 = Date(timeIntervalSince1970: 1_000)

/// After a press, a read that began before it, or one that disagrees within
/// 1.5 s, is not believed (review, 2026-10-23): the app updates its title
/// a moment after the press.
@Test func aReadThatBeganBeforeAPressIsIgnored() {
    var gate = MuteReadGate()
    let started = gate.generation
    gate.pressed(true, at: t0)
    #expect(!gate.accepts(false, startedAt: started, at: t0.addingTimeInterval(3)))
}

@Test func aDisagreeingReadSoonAfterAPressIsIgnored() {
    var gate = MuteReadGate()
    gate.pressed(true, at: t0)
    let started = gate.generation
    #expect(!gate.accepts(false, startedAt: started, at: t0.addingTimeInterval(1)))
    #expect(gate.accepts(true, startedAt: started, at: t0.addingTimeInterval(1)))
    #expect(gate.accepts(false, startedAt: started, at: t0.addingTimeInterval(2)), "after the hold the app is believed")
}

/// Starts a read at `seconds` after `t0`, if the pacer allows one.
private func start(_ pacer: inout ReadPacer, _ seconds: TimeInterval) -> Bool {
    pacer.shouldStart(at: t0.addingTimeInterval(seconds))
}

/// Never two reads at once, and a control that can't be found is looked
/// for less and less often.
@Test func oneReadAtATime() {
    var pacer = ReadPacer()
    #expect(start(&pacer, 0))
    #expect(!start(&pacer, 5))
    pacer.finished(found: true, at: t0.addingTimeInterval(5))
    #expect(!start(&pacer, 5.5))
    #expect(start(&pacer, 6))
}

@Test func failedSearchesBackOffToTenSeconds() {
    #expect((1...6).map(ReadPacer.wait(afterFailures:)) == [1, 2, 4, 8, 10, 10])
    var pacer = ReadPacer()
    for second in [0.0, 1, 3] {   // three misses: waits of 1 s, then 2 s
        #expect(start(&pacer, second))
        pacer.finished(found: false, at: t0.addingTimeInterval(second))
    }
    #expect(!start(&pacer, 6.5), "the third miss waits 4 s")
    #expect(start(&pacer, 7))
}

@Test func anAppChangeStartsAgainAtOnce() {
    var pacer = ReadPacer()
    _ = start(&pacer, 0)
    pacer.finished(found: false, at: t0)
    pacer.reset()
    #expect(start(&pacer, 0))
}

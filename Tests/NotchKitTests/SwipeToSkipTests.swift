import Testing
import CoreGraphics
@testable import NotchKit

@Test func aSwipeFiresOnceAtTheThresholdAndNotAgainUntilTheFingersLift() {
    var t = SwipeToSkipTracker()
    #expect(t.track(deltaX: 0, phase: .began, invertedFromDevice: true) == nil)
    #expect(t.track(deltaX: -20, phase: .changed, invertedFromDevice: true) == nil, "below threshold")
    #expect(t.track(deltaX: -20, phase: .changed, invertedFromDevice: true) == nil)
    #expect(t.track(deltaX: -20, phase: .changed, invertedFromDevice: true) == .next, "50pt of finger travel left: next")
    #expect(t.track(deltaX: -80, phase: .changed, invertedFromDevice: true) == nil, "a long swipe does not fire twice")
    #expect(t.track(deltaX: -30, phase: .momentum, invertedFromDevice: true) == nil, "momentum after lift-off is ignored")
    #expect(t.track(deltaX: 0, phase: .ended, invertedFromDevice: true) == nil)
    #expect(t.track(deltaX: 0, phase: .began, invertedFromDevice: true) == nil)
    #expect(t.track(deltaX: 60, phase: .changed, invertedFromDevice: true) == .previous, "finger right: previous")
}

@Test func fingerDirectionWinsOverTheScrollingSetting() {
    var natural = SwipeToSkipTracker()
    _ = natural.track(deltaX: 0, phase: .began, invertedFromDevice: true)
    #expect(natural.track(deltaX: -60, phase: .changed, invertedFromDevice: true) == .next)

    var classic = SwipeToSkipTracker()
    _ = classic.track(deltaX: 0, phase: .began, invertedFromDevice: false)
    #expect(classic.track(deltaX: 60, phase: .changed, invertedFromDevice: false) == .next,
            "classic scrolling reports the delta inverted; the finger still moved left")
}

@Test func aBackAndForthWiggleThatNeverAccumulatesDoesNotFire() {
    var t = SwipeToSkipTracker()
    _ = t.track(deltaX: 0, phase: .began, invertedFromDevice: true)
    for delta in [-30.0, 30, -30, 30, -30, 30] as [CGFloat] {
        #expect(t.track(deltaX: delta, phase: .changed, invertedFromDevice: true) == nil)
    }
}

import Foundation
import Testing
@testable import CallService

private let t0 = Date(timeIntervalSince1970: 1_000)
private let zoom = CallAppInfo(bundleID: "us.zoom.xos", name: "zoom.us", pid: 100)
private let facetime = CallAppInfo(bundleID: "com.apple.FaceTime", name: "FaceTime", pid: 200)

/// Steps the tracker every quarter second from `from` to `to` (seconds
/// after `t0`, both included), asking `holders` and `hidden` at each
/// moment, and returns each state with its time.
private func run(_ tracker: inout CallTracker, from: Double, to: Double,
                 holders: (Double) -> [CallAppInfo], hidden: (Double) -> Set<String> = { _ in [] }) -> [(Double, CallState)] {
    var states: [(Double, CallState)] = []
    var t = from
    while t <= to + 0.0001 {
        states.append((t, tracker.update(now: t0.addingTimeInterval(t), holders: holders(t), hidden: hidden(t))))
        t += 0.25
    }
    return states
}

private func isEnded(_ state: CallState) -> Bool {
    if case .ended = state { return true }
    return false
}

@Test func aHoldUnderTwoSecondsIsNoCall() {
    var tracker = CallTracker()
    let states = run(&tracker, from: 0, to: 6) { $0 <= 1.75 ? [zoom] : [] }
    #expect(states.allSatisfy { $0.1 == .idle })
}

@Test func aCallStartsAfterTwoSecondsCountingFromTheFirstTake() {
    var tracker = CallTracker()
    let states = run(&tracker, from: 0, to: 2) { _ in [zoom] }
    #expect(states.first { $0.0 == 1.75 }?.1 == .idle)
    #expect(states.last?.1 == .live(app: zoom, since: t0))
}

/// A mic switch mid-call (AirPods connecting) drops the holder for a moment.
@Test func aShortDropKeepsTheCallAndTheClock() {
    var tracker = CallTracker()
    let states = run(&tracker, from: 0, to: 20) { ($0 >= 10 && $0 < 11) ? [] : [zoom] }
    #expect(states.filter { $0.0 >= 2 }.allSatisfy { $0.1 == .live(app: zoom, since: t0) })
}

@Test func aTwoSecondDropEndsWithTheLengthUpToTheLastHold() {
    var tracker = CallTracker()
    let states = run(&tracker, from: 0, to: 70) { $0 <= 60 ? [zoom] : [] }
    #expect(states.first { $0.0 == 62 }?.1 == .live(app: zoom, since: t0))
    #expect(states.filter { isEnded($0.1) }.map(\.1) == [.ended(app: zoom, length: 60)])
    #expect(states.first { $0.0 == 62.25 }?.1 == .ended(app: zoom, length: 60))
    #expect(states.filter { $0.0 > 62.25 }.allSatisfy { $0.1 == .idle })
}

/// The call app quitting or crashing: its process simply leaves the list,
/// which reads as letting go of the mic.
@Test func aHolderVanishingEndsTheCallWithItsLength() {
    var tracker = CallTracker()
    let states = run(&tracker, from: 0, to: 40) { $0 <= 30 ? [zoom] : [] }
    #expect(states.filter { isEnded($0.1) }.map(\.1) == [.ended(app: zoom, length: 30)])
}

@Test func whenTheFirstAppLeavesTheNextCarriesOnWithoutARestart() {
    var tracker = CallTracker()
    let states = run(&tracker, from: 0, to: 40) { t in
        (t < 30 ? [zoom] : []) + (t >= 10 ? [facetime] : [])
    }
    #expect(!states.contains { isEnded($0.1) })
    #expect(states.last?.1 == .live(app: facetime, since: t0))
}

@Test func hidingTheOnlyAppEndsWithoutAnEndedMoment() {
    var tracker = CallTracker()
    let states = run(&tracker, from: 0, to: 30, holders: { $0 <= 20 ? [zoom] : [] },
                     hidden: { $0 >= 10 ? [zoom.bundleID] : [] })
    #expect(states.first { $0.0 == 9.75 }?.1 == .live(app: zoom, since: t0))
    #expect(states.filter { $0.0 >= 10 }.allSatisfy { $0.1 == .idle })
}

@Test func hidingTheShownAppHandsOverToAnotherHolder() {
    var tracker = CallTracker()
    let states = run(&tracker, from: 0, to: 30, holders: { $0 >= 5 ? [zoom, facetime] : [zoom] },
                     hidden: { $0 >= 20 ? [zoom.bundleID] : [] })
    #expect(states.first { $0.0 == 19.75 }?.1 == .live(app: zoom, since: t0))
    #expect(states.first { $0.0 == 20 }?.1 == .live(app: facetime, since: t0))
    #expect(!states.contains { isEnded($0.1) })
}

/// Bringing an app back from Settings while it holds the mic shows its call
/// at once, counting from when it took the mic.
@Test func unhidingMidHoldShowsTheCallFromItsFirstTake() {
    var tracker = CallTracker()
    let states = run(&tracker, from: 0, to: 30, holders: { _ in [zoom] },
                     hidden: { $0 < 30 ? [zoom.bundleID] : [] })
    #expect(states.filter { $0.0 < 30 }.allSatisfy { $0.1 == .idle })
    #expect(states.last?.1 == .live(app: zoom, since: t0))
}

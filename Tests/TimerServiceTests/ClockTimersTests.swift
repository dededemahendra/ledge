import Testing
import Foundation
@testable import TimerService

private let fire = Date(timeIntervalSinceReferenceDate: 810_000_000)
private func timer(_ id: String, state: Int, title: String = "", duration: Double = 900, fire: Any) -> [String: Any] {
    ["$MTTimer": ["MTTimerID": id, "MTTimerState": state, "MTTimerTitle": title, "MTTimerDuration": duration, "MTTimerFireTime": fire] as [String: Any]]
}
private func runningFire() -> [String: Any] { ["$MTTimerDate": ["MTTimerTimeDate": fire]] }
private func intervalFire() -> [String: Any] { ["$MTTimerTimeInterval": ["MTTimerTimeInterval": 900.0]] }

/// The layout observed on macOS 27 (`docs/private-api-notes.md`): an idle
/// preset, a running timer with an absolute fire date, the Clock's
/// placeholder title.
@Test func parsesTheObservedLayout() {
    let domain: [String: Any] = [
        "MTTimers": ["MTTimers": [
            timer("idle", state: 1, title: "CURRENT_TIMER", fire: intervalFire()),
            timer("run", state: 3, title: "Tea", fire: runningFire()),
        ]],
        "MTStopwatches": ["MTStopwatches": [
            ["$MTStopwatch": ["MTStopwatchIdentifier": "sw", "MTStopwatchState": 1, "MTStopwatchOffset": 0.31] as [String: Any]],
        ]],
    ]
    let snap = ClockTimerSnapshot(domain: domain)
    #expect(snap.timers == [ClockTimer(id: "run", title: "Tea", duration: 900, state: .running(fireDate: fire))])
    #expect(snap.stopwatches.isEmpty, "a stopped stopwatch is nothing to show")
    let reset = ClockTimerSnapshot(domain: ["MTStopwatches": ["MTStopwatches": [
        ["$MTStopwatch": ["MTStopwatchIdentifier": "sw", "MTStopwatchState": 0, "MTStopwatchOffset": 0.0] as [String: Any]],
    ]]])
    #expect(reset.stopwatches.isEmpty && reset.oddities.isEmpty, "reset (state 0, seen after the user reset it) is silent too")
    #expect(snap.oddities.isEmpty)
    let now = fire - 300
    #expect(snap.featured(at: now) == .timer(snap.timers[0]))
    #expect(snap.timers[0].remaining(at: now) == 300)
    #expect(abs(snap.timers[0].fraction(at: now) - 1.0 / 3) < 0.001)
    #expect(snap.timers[0].hasFired(at: fire + 1))
}

@Test func theSoonestRunningTimerWinsThenAPausedOneThenAStopwatch() {
    let domain: [String: Any] = [
        "MTTimers": ["MTTimers": [
            timer("late", state: 3, fire: ["$MTTimerDate": ["MTTimerTimeDate": fire + 600]]),
            timer("soon", state: 3, fire: runningFire()),
            timer("paused", state: 2, fire: ["$MTTimerTimeInterval": ["MTTimerTimeInterval": 120.0]]),
        ]],
    ]
    let snap = ClockTimerSnapshot(domain: domain)
    #expect(snap.featured(at: fire - 100) == .timer(snap.timers.first { $0.id == "soon" }!))
    let pausedOnly = ClockTimerSnapshot(domain: ["MTTimers": ["MTTimers": [timer("p", state: 2, fire: ["$MTTimerTimeInterval": ["MTTimerTimeInterval": 120.0]])]]])
    #expect(pausedOnly.featured(at: fire) == .timer(ClockTimer(id: "p", title: nil, duration: 900, state: .paused(remaining: 120))))
    let watchOnly = ClockTimerSnapshot(domain: ["MTStopwatches": ["MTStopwatches": [
        ["$MTStopwatch": ["MTStopwatchIdentifier": "sw", "MTStopwatchState": 2, "MTStopwatchOffset": 10.0, "MTStopwatchStartDate": fire] as [String: Any]],
    ]]])
    #expect(watchOnly.featured(at: fire + 5) == .stopwatch(ClockStopwatch(id: "sw", banked: 10, runningSince: fire)))
    #expect(watchOnly.stopwatches[0].elapsed(at: fire + 5) == 15)
}

@Test func unknownShapesAreSkippedAndDescribed() {
    let domain: [String: Any] = [
        "MTTimers": ["MTTimers": [
            timer("odd", state: 7, fire: intervalFire()),
            timer("nodate", state: 3, fire: intervalFire()),
        ]],
        "MTStopwatches": ["MTStopwatches": [
            ["$MTStopwatch": ["MTStopwatchIdentifier": "sw", "MTStopwatchState": 2, "MTStopwatchOffset": 1.0] as [String: Any]],
        ]],
    ]
    let snap = ClockTimerSnapshot(domain: domain)
    #expect(snap.timers.isEmpty && snap.stopwatches.isEmpty)
    #expect(snap.oddities.count == 3)
    #expect(ClockTimerSnapshot(domain: [:]) == .empty)
}

@Test func clockTextFitsTheEar() {
    #expect(TimerText.format(seconds: 5) == "0:05")
    #expect(TimerText.format(seconds: 754) == "12:34")
    #expect(TimerText.format(seconds: 3599) == "59:59")
    #expect(TimerText.format(seconds: 3720) == "1:02", "hours:minutes from an hour up")
    #expect(TimerText.format(seconds: -3) == "0:00")
}

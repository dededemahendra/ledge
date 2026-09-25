import Testing
import Foundation
@testable import PowerService

private func snapshot(
    _ percent: Int,
    plugged: Bool,
    charging: Bool = false,
    charged: Bool = false,
    toFull: Int? = nil
) -> PowerSnapshot {
    PowerSnapshot(
        percent: percent,
        isPluggedIn: plugged,
        isCharging: charging,
        isCharged: charged,
        timeToFullMinutes: toFull
    )
}

@Test func firstReadingEmitsNothing() {
    var d = PowerEventDeriver()
    #expect(d.events(for: snapshot(87, plugged: true, charging: true)).isEmpty,
            "launching while already plugged in must not fire a spurious activity")
}

@Test func plugInIsReported() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: false))
    let events = d.events(for: snapshot(50, plugged: true, charging: true, toFull: 42))
    #expect(events == [.pluggedIn(percent: 50, timeToFullMinutes: 42)])
}

@Test func unplugIsReported() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: true, charging: true))
    #expect(d.events(for: snapshot(50, plugged: false)) == [.unplugged(percent: 50)])
}

@Test func steadyStateEmitsNothing() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: true, charging: true))
    #expect(d.events(for: snapshot(51, plugged: true, charging: true)).isEmpty)
    #expect(d.events(for: snapshot(52, plugged: true, charging: true)).isEmpty)
}

@Test func fullyChargedFiresOnceOnly() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(99, plugged: true, charging: true))
    #expect(d.events(for: snapshot(100, plugged: true, charged: true)) == [.fullyCharged])
    #expect(d.events(for: snapshot(100, plugged: true, charged: true)).isEmpty)
}

@Test func lowBatteryFiresOncePerThresholdCrossed() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(30, plugged: false))
    #expect(d.events(for: snapshot(19, plugged: false)) == [.lowBattery(percent: 19)])
    #expect(d.events(for: snapshot(18, plugged: false)).isEmpty, "no nagging every percent")
    #expect(d.events(for: snapshot(9, plugged: false)) == [.lowBattery(percent: 9)])
    #expect(d.events(for: snapshot(4, plugged: false)) == [.lowBattery(percent: 4)])
}

@Test func thresholdsRearmAfterCharging() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(30, plugged: false))
    #expect(d.events(for: snapshot(19, plugged: false)) == [.lowBattery(percent: 19)])
    _ = d.events(for: snapshot(60, plugged: true, charging: true))
    _ = d.events(for: snapshot(60, plugged: false))
    #expect(d.events(for: snapshot(19, plugged: false)) == [.lowBattery(percent: 19)],
            "after a charge cycle the warning must be able to fire again")
}

@Test func lowBatteryDoesNotFireWhilePluggedIn() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(30, plugged: true, charging: true))
    #expect(d.events(for: snapshot(8, plugged: true, charging: true)).isEmpty)
}

@Test func plungeThroughSeveralThresholdsAtOnceReportsOnlyTheLowest() {
    // Waking from sleep can jump several thresholds in one reading.
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(40, plugged: false))
    #expect(d.events(for: snapshot(3, plugged: false)) == [.lowBattery(percent: 3)])
}

@Test func eventTitlesAreHumanReadable() {
    #expect(PowerEvent.pluggedIn(percent: 87, timeToFullMinutes: 24).activityTitle
            == "Charging · 87% · 24 min to full")
    #expect(PowerEvent.pluggedIn(percent: 87, timeToFullMinutes: nil).activityTitle
            == "Charging · 87%")
    #expect(PowerEvent.unplugged(percent: 87).activityTitle == "On battery · 87%")
    #expect(PowerEvent.fullyCharged.activityTitle == "Fully charged")
    #expect(PowerEvent.lowBattery(percent: 9).activityTitle == "Low battery · 9%")
}

/// `compactText` is the ONLY place a value can appear while a single activity
/// holds the island at notch height (the trailing ear) — `detailRow` is gated
/// off at that size. Pinning all four cases, including that a fully-charged
/// battery (which may not literally be reported at 100% by IOKit) still reads
/// "100%" rather than some other number.
@Test func compactTextIsAFewGlanceableCharacters() {
    #expect(PowerEvent.pluggedIn(percent: 87, timeToFullMinutes: 24).compactText == "87%")
    #expect(PowerEvent.pluggedIn(percent: 87, timeToFullMinutes: nil).compactText == "87%")
    #expect(PowerEvent.unplugged(percent: 87).compactText == "87%")
    #expect(PowerEvent.fullyCharged.compactText == "100%")
    #expect(PowerEvent.lowBattery(percent: 9).compactText == "9%")
}

import Testing
import AppKit
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
    #expect(d.events(for: snapshot(87, plugged: true)).isEmpty,
            "launching while already plugged in must not fire a spurious activity")
}

@Test func plugInIsReported() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: false))
    let events = d.events(for: snapshot(50, plugged: true, charging: true, toFull: 42))
    #expect(events == [.pluggedIn(percent: 50, isCharging: true, timeToFullMinutes: 42)])
}

/// The headline defect this fix-wave item exists to fix: 95% on AC, but
/// macOS reports "AC attached; not charging" (optimised battery charging,
/// or a thermal hold). The event — and therefore the title — must say so
/// rather than claiming "Charging".
@Test func plugInWhileNotChargingIsReportedAsOnAC() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(95, plugged: false))
    let events = d.events(for: snapshot(95, plugged: true, charging: false))
    #expect(events == [.pluggedIn(percent: 95, isCharging: false, timeToFullMinutes: nil)])
    #expect(events.first?.activityTitle == "On AC · 95%")
}

/// Optional fix-wave addition: nothing used to fire when the state flips
/// between charging and held (optimised-charging hold, thermal hold)
/// WITHOUT an intervening unplug/replug — the island would keep showing
/// whatever label it last had, indefinitely. `PowerEventDeriver` now
/// re-fires `.pluggedIn` with the fresh `isCharging` value whenever it
/// changes while still plugged in.
@Test func chargingAndHeldToggleWhileAlreadyPluggedInIsReported() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(95, plugged: true, charging: true, toFull: 24))

    let held = d.events(for: snapshot(95, plugged: true, charging: false))
    #expect(held == [.pluggedIn(percent: 95, isCharging: false, timeToFullMinutes: nil)])
    #expect(held.first?.activityTitle == "On AC · 95%")

    let resumed = d.events(for: snapshot(95, plugged: true, charging: true, toFull: 20))
    #expect(resumed == [.pluggedIn(percent: 95, isCharging: true, timeToFullMinutes: 20)])
    #expect(resumed.first?.activityTitle == "Charging · 95% · 20 min to full")
}

/// The steady-state case right next to the addition above: repeated
/// readings that change neither plug state nor charging state must still
/// emit nothing, exactly like `steadyStateEmitsNothing`.
@Test func steadyChargingStateEmitsNothing() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: true, charging: true))
    #expect(d.events(for: snapshot(51, plugged: true, charging: true)).isEmpty)
    #expect(d.events(for: snapshot(52, plugged: true, charging: true)).isEmpty)
}

@Test func unplugIsReported() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: true))
    #expect(d.events(for: snapshot(50, plugged: false)) == [.unplugged(percent: 50)])
}

@Test func steadyStateEmitsNothing() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: true))
    #expect(d.events(for: snapshot(51, plugged: true)).isEmpty)
    #expect(d.events(for: snapshot(52, plugged: true)).isEmpty)
}

@Test func fullyChargedFiresOnceOnly() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(99, plugged: true))
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
    _ = d.events(for: snapshot(60, plugged: true))
    _ = d.events(for: snapshot(60, plugged: false))
    #expect(d.events(for: snapshot(19, plugged: false)) == [.lowBattery(percent: 19)],
            "after a charge cycle the warning must be able to fire again")
}

@Test func lowBatteryDoesNotFireWhilePluggedIn() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(30, plugged: true))
    #expect(d.events(for: snapshot(8, plugged: true)).isEmpty)
}

@Test func plungeThroughSeveralThresholdsAtOnceReportsOnlyTheLowest() {
    // Waking from sleep can jump several thresholds in one reading.
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(40, plugged: false))
    #expect(d.events(for: snapshot(3, plugged: false)) == [.lowBattery(percent: 3)])
}

@Test func eventTitlesAreHumanReadable() {
    #expect(PowerEvent.pluggedIn(percent: 87, isCharging: true, timeToFullMinutes: 24).activityTitle
            == "Charging · 87% · 24 min to full")
    #expect(PowerEvent.pluggedIn(percent: 87, isCharging: true, timeToFullMinutes: nil).activityTitle
            == "Charging · 87%")
    #expect(PowerEvent.unplugged(percent: 87).activityTitle == "On battery · 87%")
    #expect(PowerEvent.fullyCharged.activityTitle == "Fully charged")
    #expect(PowerEvent.lowBattery(percent: 9).activityTitle == "Low battery · 9%")
}

/// The two `.pluggedIn` title branches (fix-wave item 1): actually charging
/// says so, with or without an estimate; plugged-but-not-charging must never
/// say "Charging" and never shows a stale/irrelevant estimate.
@Test func pluggedInTitleTellsChargingFromHeldApart() {
    #expect(PowerEvent.pluggedIn(percent: 95, isCharging: true, timeToFullMinutes: 24).activityTitle
            == "Charging · 95% · 24 min to full")
    #expect(PowerEvent.pluggedIn(percent: 95, isCharging: true, timeToFullMinutes: nil).activityTitle
            == "Charging · 95%")
    #expect(PowerEvent.pluggedIn(percent: 95, isCharging: false, timeToFullMinutes: nil).activityTitle
            == "On AC · 95%")
    #expect(
        PowerEvent.pluggedIn(percent: 95, isCharging: false, timeToFullMinutes: 24).activityTitle
            == "On AC · 95%",
        "not charging means no time-to-full estimate, even if IOKit somehow still reports one"
    )
}

/// `compactText` is the ONLY place a value can appear while a single activity
/// holds the island at notch height (the trailing ear) — `detailRow` is gated
/// off at that size. Pinning all four cases, including that a fully-charged
/// battery (which may not literally be reported at 100% by IOKit) still reads
/// "100%" rather than some other number.
@Test func compactTextIsAFewGlanceableCharacters() {
    #expect(PowerEvent.pluggedIn(percent: 87, isCharging: true, timeToFullMinutes: 24).compactText == "87%")
    #expect(PowerEvent.pluggedIn(percent: 87, isCharging: false, timeToFullMinutes: nil).compactText == "87%")
    #expect(PowerEvent.unplugged(percent: 87).compactText == "87%")
    #expect(PowerEvent.fullyCharged.compactText == "100%")
    #expect(PowerEvent.lowBattery(percent: 9).compactText == "9%")
}

/// The ear glyph follows the state (2026-09-28); the ear shows no words.
@Test func glyphsFollowTheState() {
    #expect(PowerEvent.pluggedIn(percent: 95, isCharging: true, timeToFullMinutes: 20).symbolName == "battery.100percent.bolt",
            "the menu bar's own charging glyph")
    #expect(PowerEvent.pluggedIn(percent: 95, isCharging: false, timeToFullMinutes: nil).symbolName == "powerplug.fill")
    #expect(PowerEvent.fullyCharged.symbolName == "battery.100percent")
    #expect(PowerEvent.unplugged(percent: 87).symbolName == "battery.75percent")
    #expect(PowerEvent.unplugged(percent: 95).symbolName == "battery.100percent")
    #expect(PowerEvent.lowBattery(percent: 9).symbolName == "battery.0percent")
    #expect(PowerEvent.lowBattery(percent: 19).symbolName == "battery.25percent")
    #expect(PowerEvent.batterySymbol(percent: 50).hasPrefix("battery.50"))
}

@Test func tintFollowsTheSystemsOwnBatteryColours() {
    #expect(PowerEvent.pluggedIn(percent: 40, isCharging: true, timeToFullMinutes: 30).tint == .positive, "green while charging")
    #expect(PowerEvent.fullyCharged.tint == .positive)
    #expect(PowerEvent.lowBattery(percent: 9).tint == .warning, "red when low")
    #expect(PowerEvent.unplugged(percent: 80).tint == nil, "plain on battery")
    #expect(PowerEvent.pluggedIn(percent: 80, isCharging: false, timeToFullMinutes: nil).tint == nil, "held on AC is not charging")
}

/// Every glyph the power blip can show must exist in SF Symbols on this
/// system, or the ear would be empty for that state.
@Test func everyPowerGlyphResolvesOnThisSystem() {
    let events: [PowerEvent] = [
        .pluggedIn(percent: 40, isCharging: true, timeToFullMinutes: 30),
        .pluggedIn(percent: 40, isCharging: false, timeToFullMinutes: nil),
        .fullyCharged,
        .unplugged(percent: 5), .unplugged(percent: 20), .unplugged(percent: 50), .unplugged(percent: 75), .unplugged(percent: 100),
        .lowBattery(percent: 9),
    ]
    for event in events {
        #expect(NSImage(systemSymbolName: event.symbolName, accessibilityDescription: nil) != nil,
                "\(event.symbolName) is not an SF Symbol here")
    }
}

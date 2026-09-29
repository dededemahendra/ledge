import Testing
@testable import HUDService

@Test func firstReadingEstablishesBaselineWithoutFiring() {
    var d = HUDEventDeriver()
    #expect(d.volumeChanged(level: 0.4, muted: false) == nil,
            "launching must not throw a HUD on screen")
    #expect(d.brightnessChanged(level: 0.6) == nil)
}

@Test func aRealChangeFires() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    #expect(d.volumeChanged(level: 0.5, muted: false) == .volume(level: 0.5, muted: false))
}

@Test func anIdenticalReadingDoesNotFire() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    #expect(d.volumeChanged(level: 0.4, muted: false) == nil)
}

@Test func imperceptibleJitterIsIgnored() {
    // CoreAudio reports floats; a device can report 0.400001 repeatedly.
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    #expect(d.volumeChanged(level: 0.4001, muted: false) == nil)
    #expect(d.volumeChanged(level: 0.4 + HUDEventDeriver.minimumDelta * 2, muted: false) != nil)
}

@Test func muteTogglingFiresEvenAtTheSameLevel() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    #expect(d.volumeChanged(level: 0.4, muted: true) == .volume(level: 0.4, muted: true))
    #expect(d.volumeChanged(level: 0.4, muted: false) == .volume(level: 0.4, muted: false))
}

@Test func brightnessAndVolumeTrackIndependently() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    _ = d.brightnessChanged(level: 0.6)
    #expect(d.brightnessChanged(level: 0.7) == .brightness(level: 0.7))
    #expect(d.volumeChanged(level: 0.4, muted: false) == nil)
}

@Test func levelsAreClampedToUnitRange() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.5, muted: false)
    #expect(d.volumeChanged(level: 1.8, muted: false) == .volume(level: 1.0, muted: false))
    #expect(d.volumeChanged(level: -0.3, muted: false) == .volume(level: 0.0, muted: false))
}

// Review Focus 1: rebinding to a new device must not suppress the next real change.
/// An output-device switch must re-baseline volume WITHOUT losing the
/// brightness baseline: the display did not change, only the speakers did.
@Test func resetVolumeRebaselinesVolumeOnlyAndKeepsBrightness() {
    var d = HUDEventDeriver()
    #expect(d.volumeChanged(level: 0.3, muted: false) == nil)
    #expect(d.brightnessChanged(level: 0.5) == nil)

    d.resetVolume()
    #expect(d.volumeChanged(level: 0.8, muted: false) == nil,
            "the new device's own level is a baseline, not a change — no HUD on AirPods connecting")
    #expect(d.volumeChanged(level: 0.85, muted: false) == .volume(level: 0.85, muted: false),
            "and the next real change fires against the new baseline")
    #expect(d.brightnessChanged(level: 0.6) == .brightness(level: 0.6),
            "brightness keeps its baseline across a volume-only reset")
}

@Test func resetForcesTheNextReadingToBeTreatedAsFresh() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    d.reset()
    #expect(d.volumeChanged(level: 0.4, muted: false) == nil,
            "reset re-baselines; the first post-reset reading is a baseline")
    #expect(d.volumeChanged(level: 0.55, muted: false) != nil)
}

@Test func displayPropertiesAreUseful() {
    #expect(HUDEvent.volume(level: 0.5, muted: false).barFill == 0.5)
    #expect(HUDEvent.volume(level: 0.5, muted: true).barFill == 0,
            "a muted bar must read as empty even at level 0.5")
    #expect(HUDEvent.volume(level: 0.5, muted: true).symbolName == "speaker.slash.fill")
    #expect(HUDEvent.brightness(level: 0.25).barFill == 0.25)
    #expect(HUDEvent.brightness(level: 0.25).symbolName == "sun.max.fill")
    #expect(HUDEvent.volume(level: 0.5, muted: false).activityTitle == "Sound",
            "no digits — the bar beside the title carries the value")
    #expect(HUDEvent.volume(level: 0.5, muted: true).activityTitle == "Sound",
            "mute is told by the slashed glyph and the empty bar, not by swapping the word")
    #expect(HUDEvent.brightness(level: 0.06).activityTitle == "Display")
}

/// `compactText` is the ONLY place a value can appear while a single activity holds
/// the island at notch height (the trailing ear) — `detailRow` is gated off at that
/// size, and `activityTitle` has nowhere to render. The brief's own prose calls for
/// pinning all three cases here (muted must yield "Muted", not a percentage), but its
/// Step 2 code block omitted the assertions — added here since this is exactly the
/// defect class (compactText silently missing) that Plan A shipped once already.
@Test func compactTextIsAFewGlanceableCharacters() {
    #expect(HUDEvent.volume(level: 0.5, muted: false).compactText == "50%")
    #expect(HUDEvent.volume(level: 0.5, muted: true).compactText == "0%",
            "mute reads as zero beside the slashed glyph, like the system overlay's empty bar")
    #expect(HUDEvent.brightness(level: 0.25).compactText == "25%")
}

// Regression: the old implementation rebaselined `last*` unconditionally via
// `defer`, so each reading was compared against the immediately preceding
// *observed* value rather than the last one that actually fired. A slow
// Control Centre slider drag produces a stream of sub-`minimumDelta` deltas —
// each individually too small to fire, and each moving the baseline — so
// volume could move from 40% to 80% while zero HUD events fired.
@Test func slowDragAcrossManySubThresholdVolumeStepsStillFiresAtLeastOnce() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.40, muted: false)   // baseline

    var firedCount = 0
    var level = 0.40
    while level < 0.80 {
        level += 0.002
        if d.volumeChanged(level: level, muted: false) != nil {
            firedCount += 1
        }
    }

    #expect(firedCount > 0,
            "a slow slider drag from 40% to 80% in sub-threshold steps must fire at least one HUD event")
}

// Same defect class, same fix shape, applied to brightness.
@Test func slowDragAcrossManySubThresholdBrightnessStepsStillFiresAtLeastOnce() {
    var d = HUDEventDeriver()
    _ = d.brightnessChanged(level: 0.40)   // baseline

    var firedCount = 0
    var level = 0.40
    while level < 0.80 {
        level += 0.002
        if d.brightnessChanged(level: level) != nil {
            firedCount += 1
        }
    }

    #expect(firedCount > 0,
            "a slow brightness drag from 40% to 80% in sub-threshold steps must fire at least one HUD event")
}

// Nothing currently pins the boundary as inclusive (`>=` vs `>`).
@Test func minimumDeltaBoundaryFiresInclusively() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.40, muted: false)
    let boundary = 0.40 + HUDEventDeriver.minimumDelta
    #expect(d.volumeChanged(level: boundary, muted: false) == .volume(level: boundary, muted: false))
}

/// The level symbol is CONSTANT across the whole range — the level renders
/// through SF Symbols variable-value (`variableValue: barFill` at the ear),
/// not by swapping band symbols (wave.1/2/3), which fired a crossfade at
/// every band edge mid-slide. Only mute, a real state change, swaps glyphs.
@Test func levelSymbolIsConstantSoTheGlyphNeverSwapsMidSlide() {
    for level in [0.0, 0.2, 0.5, 0.8, 1.0] {
        #expect(HUDEvent.volume(level: level, muted: false).symbolName == "speaker.wave.3.fill")
        #expect(HUDEvent.brightness(level: level).symbolName == "sun.max.fill")
    }
}

/// Brightness keys snap to sixteenths; the display's own adjustments do not.
@Test func keyGridAcceptsSixteenthsAndRejectsTheDisplaysOwnDimming() {
    for k in 0...16 { #expect(HUDEventDeriver.isOnKeyGrid(Double(k) / 16)) }
    #expect(HUDEventDeriver.isOnKeyGrid(0.7501), "float jitter around a step is still a step")
    #expect(!HUDEventDeriver.isOnKeyGrid(0.525), "0.75 dimmed by 30% on battery")
    #expect(!HUDEventDeriver.isOnKeyGrid(0.71), "auto-brightness drift")
    #expect(!HUDEventDeriver.isOnKeyGrid(0.03))
}

@Test func capsLockBaselinesThenFiresOnEveryToggle() {
    var d = HUDEventDeriver()
    #expect(d.capsLockChanged(on: true) == nil, "already on at launch is not news")
    #expect(d.capsLockChanged(on: true) == nil, "polls that see no change are silent")
    #expect(d.capsLockChanged(on: false) == .capsLock(on: false))
    #expect(d.capsLockChanged(on: true) == .capsLock(on: true))
    d.reset()
    #expect(d.capsLockChanged(on: false) == nil, "reset re-baselines")
}

@Test func capsLockPresentsAsGlyphPlusOnOff() {
    #expect(HUDEvent.capsLock(on: true).symbolName == "capslock.fill")
    #expect(HUDEvent.capsLock(on: false).symbolName == "capslock")
    #expect(HUDEvent.capsLock(on: true).compactText == "On")
    #expect(HUDEvent.capsLock(on: false).compactText == "Off")
    #expect(HUDEvent.capsLock(on: true).activityTitle == "Caps Lock")
    #expect(HUDEvent.capsLock(on: true).barFill == nil, "no level to light the glyph by")
    #expect(HUDEvent.volume(level: 0.5, muted: false).barFill == 0.5, "volume still carries its level")
}

/// The observer reads the same session state the system does; on a test
/// box this simply must not crash and must agree with itself.
@Test func capsLockStateIsReadableWithoutPermission() {
    let a = CapsLockObserver.isCapsLockOn()
    let b = CapsLockObserver.isCapsLockOn()
    #expect(a == b)
}

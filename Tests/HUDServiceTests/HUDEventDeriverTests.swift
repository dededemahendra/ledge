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
    #expect(HUDEvent.volume(level: 0.0, muted: false).symbolName == "speaker.fill")
    #expect(HUDEvent.volume(level: 0.8, muted: false).symbolName == "speaker.wave.3.fill")
    #expect(HUDEvent.brightness(level: 0.25).barFill == 0.25)
    #expect(HUDEvent.brightness(level: 0.25).symbolName == "sun.max.fill")
    #expect(HUDEvent.volume(level: 0.5, muted: false).activityTitle == "Volume 50%")
    #expect(HUDEvent.volume(level: 0.5, muted: true).activityTitle == "Muted")
    #expect(HUDEvent.brightness(level: 0.06).activityTitle == "Brightness 6%")
}

/// `compactText` is the ONLY place a value can appear while a single activity holds
/// the island at notch height (the trailing ear) — `detailRow` is gated off at that
/// size, and `activityTitle` has nowhere to render. The brief's own prose calls for
/// pinning all three cases here (muted must yield "Muted", not a percentage), but its
/// Step 2 code block omitted the assertions — added here since this is exactly the
/// defect class (compactText silently missing) that Plan A shipped once already.
@Test func compactTextIsAFewGlanceableCharacters() {
    #expect(HUDEvent.volume(level: 0.5, muted: false).compactText == "50%")
    #expect(HUDEvent.volume(level: 0.5, muted: true).compactText == "Muted",
            "muted must yield \"Muted\", not a percentage")
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

// Only muted, 0.0 and 0.8 were covered; the two middle bands were not.
@Test func symbolNameCoversTheMiddleBands() {
    #expect(HUDEvent.volume(level: 0.2, muted: false).symbolName == "speaker.wave.1.fill")
    #expect(HUDEvent.volume(level: 0.5, muted: false).symbolName == "speaker.wave.2.fill")
}

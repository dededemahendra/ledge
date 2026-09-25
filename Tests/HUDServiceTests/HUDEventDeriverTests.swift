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

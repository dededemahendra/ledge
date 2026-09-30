import Testing
@testable import FocusService

/// The sizes observed on 2026-09-30: ~1270 bytes with no Focus, ~1900
/// with one on, a couple of bytes' drift on rewrites.
@Test func aJumpUpIsOnADropIsOffAndTheFirstSampleIsSilent() {
    var deriver = FocusSizeDeriver()
    #expect(deriver.sample(size: 1979) == nil, "on at launch: not news")
    #expect(deriver.sample(size: 1271) == .off)
    #expect(deriver.sample(size: 1902) == .on)
    #expect(deriver.sample(size: 1904) == nil, "a rewrite at the same size: switched modes, still on")
    #expect(deriver.sample(size: 1267) == .off)
    #expect(deriver.sample(size: 1902) == .on)
}

@Test func glyphsAndTextFollowTheState() {
    #expect(FocusEvent.on.symbolName == "moon.fill" && FocusEvent.on.compactText == "On")
    #expect(FocusEvent.off.symbolName == "moon" && FocusEvent.off.compactText == "Off")
}

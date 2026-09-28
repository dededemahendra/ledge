import Testing
@testable import HUDService

/// `data1` packs key code << 16 | state << 8 | repeat. Built here the same
/// way the kernel does, so the decoder is tested against the layout, not
/// against itself.
private func data1(code: UInt32, down: Bool, repeating: Bool = false) -> Int {
    Int(code) << 16 | (down ? 0x0A : 0x0B) << 8 | (repeating ? 1 : 0)
}

@Test func decodesEveryReplacedKeyDownUpAndRepeat() {
    for key in MediaKey.allCases {
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(code: key.rawValue, down: true))
                == MediaKeyPress(key: key, isDown: true, isRepeat: false))
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(code: key.rawValue, down: false))
                == MediaKeyPress(key: key, isDown: false, isRepeat: false))
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(code: key.rawValue, down: true, repeating: true))
                == MediaKeyPress(key: key, isDown: true, isRepeat: true))
    }
}

@Test func ignoresOtherSubtypesAndOtherKeys() {
    #expect(MediaKeyDecoder.decode(subtype: 7, data1: data1(code: 0, down: true)) == nil,
            "only NX_SUBTYPE_AUX_CONTROL_BUTTONS carries media keys")
    #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(code: 16, down: true)) == nil, "play/pause passes through")
    #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(code: 21, down: true)) == nil, "keyboard backlight passes through")
}

@Test func coarseStepsMoveASixteenthAndSnapToTheGrid() {
    #expect(MediaKeyStepper.step(0.5, up: true, fine: false) == 0.5625)
    #expect(MediaKeyStepper.step(0.5, up: false, fine: false) == 0.4375)
    #expect(MediaKeyStepper.step(0.53, up: true, fine: false) == 0.5625, "off-grid input snaps like the system keys")
    #expect(MediaKeyStepper.step(0.53, up: false, fine: false) == 0.4375)
}

@Test func fineStepsMoveASixtyFourth() {
    #expect(MediaKeyStepper.step(0.5, up: true, fine: true) == 0.5 + 1.0 / 64)
    #expect(MediaKeyStepper.step(0.5, up: false, fine: true) == 0.5 - 1.0 / 64)
}

@Test func stepsClampAtTheEnds() {
    #expect(MediaKeyStepper.step(1.0, up: true, fine: false) == 1.0)
    #expect(MediaKeyStepper.step(0.0, up: false, fine: false) == 0.0)
    #expect(MediaKeyStepper.step(1.5, up: false, fine: false) == 0.9375, "garbage above 1 is treated as 1")
    #expect(MediaKeyStepper.step(-1, up: true, fine: false) == 0.0625)
}

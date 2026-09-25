import Testing
import CoreGraphics
@testable import NotchKit

struct FakeScreen: ScreenDescribing {
    var frame: CGRect
    var safeAreaTopInset: CGFloat
    var auxiliaryTopLeftMaxX: CGFloat?
    var auxiliaryTopRightMinX: CGFloat?
    var isBuiltIn: Bool = true

    /// The measured built-in display of the target machine.
    static let measured = FakeScreen(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        safeAreaTopInset: 32,
        auxiliaryTopLeftMaxX: 645.5,
        auxiliaryTopRightMinX: 824.5
    )
}

@Test func measuredScreenYieldsTheMeasuredNotch() throws {
    let rect = try #require(NotchGeometry.notchRect(for: FakeScreen.measured))
    #expect(rect.width == 179)
    #expect(rect.height == 32)
    #expect(rect.minX == 645.5)
    #expect(rect.minY == 0)
}

@Test func notchIsHorizontallyCentred() throws {
    let screen = FakeScreen.measured
    let rect = try #require(NotchGeometry.notchRect(for: screen))
    #expect(abs(rect.midX - screen.frame.midX) < 0.01)
}

// Review Focus 2: no notch must mean no island, never a guessed rect.
@Test func screenWithoutAuxiliaryAreasHasNoNotch() {
    var screen = FakeScreen.measured
    screen.auxiliaryTopLeftMaxX = nil
    screen.auxiliaryTopRightMinX = nil
    #expect(NotchGeometry.notchRect(for: screen) == nil)
}

@Test func screenWithoutTopSafeAreaHasNoNotch() {
    var screen = FakeScreen.measured
    screen.safeAreaTopInset = 0
    #expect(NotchGeometry.notchRect(for: screen) == nil)
}

// Review Focus 3: an external display is not a host, even if it reports oddities.
@Test func externalScreenHasNoNotch() {
    var screen = FakeScreen.measured
    screen.isBuiltIn = false
    #expect(NotchGeometry.notchRect(for: screen) == nil)
}

@Test func degenerateAuxiliaryOrderingHasNoNotch() {
    var screen = FakeScreen.measured
    screen.auxiliaryTopLeftMaxX = 824.5
    screen.auxiliaryTopRightMinX = 645.5   // inverted
    #expect(NotchGeometry.notchRect(for: screen) == nil)
}

@Test func scaledModeYieldsDifferentButValidGeometry() throws {
    // A "more space" scaling mode: wider logical screen, proportionally narrower notch.
    let screen = FakeScreen(
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        safeAreaTopInset: 37,
        auxiliaryTopLeftMaxX: 751,
        auxiliaryTopRightMinX: 959
    )
    let rect = try #require(NotchGeometry.notchRect(for: screen))
    #expect(rect.width == 208)
    #expect(rect.height == 37)
}

import Testing
import CoreGraphics
@testable import NotchKit

// Fix-wave item 2: `refreshInteractiveRegion` (clicks) claimed a `NotchShape`
// path while `reevaluateHover` tested a plain `CGRect`. These tests exercise
// the two static, pure geometry helpers `NotchPresenter` now shares between
// them (`islandPath(for:)`/`localPoint(_:on:)`) directly — no real
// `NSScreen.builtIn`/`NSEvent.mouseLocation` needed, so they are fast and
// fully deterministic regardless of what hardware runs the suite.

/// Same shape as `NotchMetrics(notchRect: measuredNotch).expanded` used
/// elsewhere (`NotchShapeTests`), hardcoded here to keep this file decoupled
/// from `NotchMetrics`/notch-rect specifics — only the shape parameters
/// themselves matter for this geometry.
private let testParameters = NotchShapeParameters(width: 390, height: 118, bottomRadius: 26, outerFillet: 13)
private let testScreenFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)

/// The naive region the OLD `reevaluateHover` tested, reconstructed here
/// (not imported from production code — it no longer exists) purely to
/// prove it disagrees with the real path at the two defect points below.
private func naiveRect(_ parameters: NotchShapeParameters) -> CGRect {
    CGRect(
        x: NotchPresenter.canvas.midX - parameters.width / 2, y: 0,
        width: parameters.width, height: parameters.height
    )
}

// MARK: - localPoint(_:on:)

@Test func localPointMapsScreenTopCentreToCanvasTopCentre() {
    let global = CGPoint(x: testScreenFrame.midX, y: testScreenFrame.maxY)
    let local = NotchPresenter.localPoint(global, on: testScreenFrame)
    #expect(abs(local.x - NotchPresenter.canvas.width / 2) < 0.001)
    #expect(abs(local.y) < 0.001)
}

@Test func localPointTracksVerticalDistanceBelowTheScreenTop() {
    let global = CGPoint(x: testScreenFrame.midX, y: testScreenFrame.maxY - 42)
    let local = NotchPresenter.localPoint(global, on: testScreenFrame)
    #expect(abs(local.y - 42) < 0.001)
}

/// A built-in panel docked beside an external primary display carries a
/// desktop offset in its frame — `NotchGeometryTests` already proves this
/// cancels out for the notch rect itself; this pins the same property for
/// hover's coordinate conversion.
@Test func localPointIsIndependentOfScreenOffsetFromTheDesktopOrigin() {
    let offset: CGFloat = 1920
    let screenFrame = testScreenFrame.offsetBy(dx: offset, dy: 0)
    let global = CGPoint(x: screenFrame.midX, y: screenFrame.maxY - 10)
    let local = NotchPresenter.localPoint(global, on: screenFrame)
    #expect(abs(local.x - NotchPresenter.canvas.width / 2) < 0.001)
    #expect(abs(local.y - 10) < 0.001)
}

// MARK: - islandPath(for:) sanity

@Test func islandPathContainsItsOwnCentreAndExcludesAFarAwayPoint() {
    let path = NotchPresenter.islandPath(for: testParameters)
    let centre = CGPoint(x: NotchPresenter.canvas.midX, y: testParameters.height / 2)
    #expect(path.contains(centre))
    #expect(path.contains(CGPoint(x: 5, y: 5)) == false)
}

// MARK: - The two defects fix-wave item 2 describes

/// "the island's rounded bottom corners are inside the rect but outside the
/// path, so there is a corner region where the controller believes it is
/// hovered — suppressing TTL expiry — while clicks pass through."
///
/// local (126, 117) sits 1pt inside the naive rect's bottom-left corner —
/// comfortably inside the plain `width x height` box — but is outside the
/// circle rounding that corner (radius 26 centred at (151, 92)), so it is
/// cut off by the actual path.
@Test func roundedBottomCornerIsInsideTheNaiveRectButOutsideTheRealPath() {
    let global = CGPoint(
        x: testScreenFrame.midX + 126 - NotchPresenter.canvas.width / 2,
        y: testScreenFrame.maxY - 117
    )
    let local = NotchPresenter.localPoint(global, on: testScreenFrame)

    #expect(naiveRect(testParameters).contains(local),
            "sanity: point must land inside the rect the old code tested")
    #expect(
        NotchPresenter.islandPath(for: testParameters).contains(local) == false,
        "the rounded corner must read as outside the real path, same as a click there would"
    )
}

/// "the concave outer fillets make the path wider than the rect, so there is
/// a band where clicks are claimed without hover."
///
/// local (124, 5) sits just outside the naive rect's left edge (left = 125)
/// but is outside the concave arc's circle (radius 13 centred at (112, 13)),
/// which is the FILLED side of that boundary — see
/// `NotchShapeTests.outerFilletsAreConcaveNotConvex` for the same circle
/// used the other way (a point INSIDE that circle is the scooped-out side).
@Test func concaveFilletBandIsOutsideTheNaiveRectButInsideTheRealPath() {
    let global = CGPoint(
        x: testScreenFrame.midX + 124 - NotchPresenter.canvas.width / 2,
        y: testScreenFrame.maxY - 5
    )
    let local = NotchPresenter.localPoint(global, on: testScreenFrame)

    #expect(naiveRect(testParameters).contains(local) == false,
            "sanity: point must land outside the rect the old code tested")
    #expect(
        NotchPresenter.islandPath(for: testParameters).contains(local),
        "the concave fillet band must read as inside the real path, same as a click there would"
    )
}

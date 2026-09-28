import Testing
import CoreGraphics
import SwiftUI
@testable import NotchKit

private let measuredNotch = CGRect(x: 645.5, y: 0, width: 179, height: 32)

@Test func collapsedParametersMatchTheMeasuredNotch() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(metrics.collapsed.width == 179)
    #expect(metrics.collapsed.height == 32)
    #expect(metrics.collapsed.bottomRadius == 9)
    #expect(metrics.collapsed.outerFillet == 0)
}

@Test func specifiedTargetGeometryIsHonoured() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(metrics.peek.height == 38)                  // notch + 6
    #expect(metrics.oneActivity.width == 255)
    #expect(metrics.oneActivity.height == 32)
    #expect(metrics.twoActivities.width == 342)
    #expect(metrics.twoActivities.height == 62)
    #expect(metrics.expanded.width == 390)
    #expect(metrics.expanded.height == 168)   // 118 -> 140 -> 168, matching Alcove's card proportions
    #expect(metrics.expanded.bottomRadius == 26)
    #expect(metrics.expanded.outerFillet == 13)
}

/// The volume/brightness HUD is the one island whose width is DERIVED from the
/// notch rather than fixed: it exists to give each ear exactly
/// `hudEarWidth` of room for glyph + label / bar, whatever the hardware.
@Test func hudSizeGivesEachEarTheMeasuredWidth() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(NotchMetrics.hudEarWidth == 90)
    #expect(metrics.hud.width == 359)                    // 179 + 2 * 90
    #expect(metrics.hud.height == 32, "still notch-height: ears first, never taller")
    #expect(metrics.earWidth(forIslandWidth: metrics.hud.width) == 90)
    #expect(metrics.hud.bottomRadius == metrics.oneActivity.bottomRadius)
    #expect(metrics.hud.outerFillet == metrics.oneActivity.outerFillet)

    let tall = NotchMetrics(notchRect: CGRect(x: 751, y: 0, width: 208, height: 37))
    #expect(tall.earWidth(forIslandWidth: tall.hud.width) == 90, "the ear, not the island, is the constant")
    #expect(tall.hud.height == 37)
}

@Test func earWidthLeavesRoomBesideTheHole() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    // Exercise the public function later tasks consume, not the arithmetic inline.
    #expect(metrics.earWidth(forIslandWidth: metrics.oneActivity.width) == 38)
    #expect(metrics.earWidth(forIslandWidth: metrics.twoActivities.width) == 81.5)
    #expect(metrics.earWidth(forIslandWidth: 100) == 0, "narrower than the notch leaves no ear")
}

/// The spec's target heights assume the measured 32pt notch. A scaling mode with
/// a taller notch must not make the island shrink, nor leave the cutout uncovered.
@Test func restingHeightsNeverShrinkAndAlwaysCoverTheCutout() {
    // A "more space" scaling mode: notch 208 x 37, matching NotchGeometry's fixture.
    let tall = NotchMetrics(notchRect: CGRect(x: 751, y: 0, width: 208, height: 37))

    #expect(tall.collapsed.width == 208, "collapsed size tracks the hardware")
    #expect(tall.collapsed.height == 37)
    #expect(tall.peek.height > tall.collapsed.height, "peek grows, never shrinks")

    let chain = [
        tall.collapsed.height,
        tall.oneActivity.height,
        tall.twoActivities.height,
        tall.expanded.height,
    ]
    for height in chain {
        #expect(height >= 37, "the island may never be shorter than the cutout it covers")
    }
    #expect(chain == chain.sorted(), "the island must never shrink as it reveals more")
}

/// Bounding-box assertions are fixed by the arc's endpoints, so a CONVEX fillet of
/// the same radius and endpoints would satisfy them identically. This pins the
/// curvature direction itself.
@Test func outerFilletsAreConcaveNotConvex() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let p = metrics.expanded
    let path = NotchShape(p).path(in: canvas)

    let left = canvas.midX - p.width / 2
    let top = canvas.minY

    // Halfway along the diagonal between the flat top edge and the point where the
    // fillet meets the body's side. A concave fillet scoops this out of the shape;
    // a convex one would include it.
    let scooped = CGPoint(x: left - p.outerFillet / 2, y: top + p.outerFillet / 2)
    #expect(path.contains(scooped) == false,
            "the fillet must curve away from the body, not bulge into it")

    // Controls: the body is filled, and the flat top edge spans the fillet flare.
    #expect(path.contains(CGPoint(x: canvas.midX, y: top + p.height / 2)))
    #expect(path.contains(CGPoint(x: left, y: top + 1)))
}

@Test func interpolationIsMonotonicAndBounded() {
    let a = NotchShapeParameters(width: 179, height: 32, bottomRadius: 9, outerFillet: 0)
    let b = NotchShapeParameters(width: 390, height: 168, bottomRadius: 26, outerFillet: 13)
    var previousWidth = a.width
    var previousHeight = a.height
    for step in 0...10 {
        let p = Double(step) / 10
        let mid = NotchShapeParameters.lerp(a, b, p)
        #expect(mid.width >= previousWidth)
        #expect(mid.height >= previousHeight)
        #expect(mid.outerFillet >= 0)          // never negative — the seam would invert
        #expect(mid.bottomRadius >= 0)
        previousWidth = mid.width
        previousHeight = mid.height
    }
    #expect(NotchShapeParameters.lerp(a, b, 0) == a)
    #expect(NotchShapeParameters.lerp(a, b, 1) == b)
}

@Test func animatableDataRoundTrips() {
    var p = NotchShapeParameters(width: 200, height: 40, bottomRadius: 12, outerFillet: 4)
    let captured = p.animatableData
    p.width = 0; p.height = 0; p.bottomRadius = 0; p.outerFillet = 0
    p.animatableData = captured
    #expect(p.width == 200)
    #expect(p.height == 40)
    #expect(p.bottomRadius == 12)
    #expect(p.outerFillet == 4)
}

@Test func collapsedPathBoundsEqualTheNotch() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let bounds = NotchShape(metrics.collapsed).path(in: canvas).boundingRect
    // Fillet is 0 when collapsed, so bounds are exactly the island body.
    #expect(abs(bounds.width - 179) < 0.5)
    #expect(abs(bounds.height - 32) < 0.5)
    #expect(abs(bounds.midX - canvas.midX) < 0.5)
    #expect(abs(bounds.minY - canvas.minY) < 0.5)
}

@Test func expandedPathIsWiderByExactlyTwoFillets() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let bounds = NotchShape(metrics.expanded).path(in: canvas).boundingRect
    #expect(abs(bounds.width - (390 + 2 * 13)) < 0.5)
    #expect(abs(bounds.height - 168) < 0.5)
}

@Test func pathIsAlwaysWeldedToTheTopEdge() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    for p in [metrics.collapsed, metrics.peek, metrics.oneActivity, metrics.expanded] {
        let bounds = NotchShape(p).path(in: canvas).boundingRect
        #expect(abs(bounds.minY - canvas.minY) < 0.5, "island must stay welded to the bezel")
    }
}

@Test func contentOpacityRampsOverTheSpecifiedWindow() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(metrics.contentOpacity(progress: 0.0) == 0)
    #expect(metrics.contentOpacity(progress: 0.45) == 0)
    #expect(metrics.contentOpacity(progress: 0.83) == 1)
    #expect(metrics.contentOpacity(progress: 1.0) == 1)
    let mid = metrics.contentOpacity(progress: 0.64)
    #expect(mid > 0.4 && mid < 0.6)
}

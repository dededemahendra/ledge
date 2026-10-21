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
    #expect(metrics.expanded.width == 356)
    #expect(metrics.expanded.height == 168)   // 118 -> 140 -> 168, matching Alcove's card proportions
    #expect(metrics.expanded.bottomRadius == 26)
    #expect(metrics.expanded.outerFillet == 13)
}

@Test func captionedIslandIsOneRowTallerThanTheNotch() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(metrics.captioned.height == 32 + NotchMetrics.captionRowHeight)
    #expect(metrics.captioned.width > metrics.oneActivity.width, "wider ears for the artwork and bars")
    #expect(metrics.captioned.width < metrics.expanded.width)
}

/// On a real notch, hidden is the notch itself: invisible against the
/// hardware.
@Test func aRealNotchRetractsToTheNotchItself() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(metrics.retracted == metrics.collapsed)
}

/// The output picker grows the expanded panel by exactly its rows.
@Test func expandedGrowsByOneRowPerOutputWhenThePickerIsOpen() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(metrics.expanded(outputRows: 0) == metrics.expanded)
    #expect(metrics.expanded(outputRows: 3).height == 168 + NotchMetrics.outputListInset + 3 * NotchMetrics.outputRowHeight)
    #expect(metrics.expanded(outputRows: 3).width == metrics.expanded.width, "only the height changes")
    #expect(metrics.expanded(outputRows: 3).bottomRadius == metrics.expanded.bottomRadius)
}

@Test func earWidthLeavesRoomBesideTheHole() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    // Exercise the public function later tasks consume, not the arithmetic inline.
    #expect(metrics.earWidth(forIslandWidth: metrics.oneActivity.width) == 38)
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
    let b = NotchShapeParameters(width: 356, height: 168, bottomRadius: 26, outerFillet: 13)
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
    #expect(abs(bounds.width - (356 + 2 * 13)) < 0.5)
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

// MARK: - The pill (2026-10-21)

private let pillCapsule = NotchShapeParameters(
    width: 120, height: 32, bottomRadius: 16, outerFillet: 0, topInset: 4, topRadius: 16
)

@Test func newValuesDefaultToZeroSoTheNotchOutlineIsUnchanged() {
    let p = NotchShapeParameters(width: 255, height: 32, bottomRadius: 12, outerFillet: 6)
    #expect(p.topInset == 0)
    #expect(p.topRadius == 0)
}

@Test func pillFloatsAtItsInset() {
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let bounds = NotchShape(pillCapsule).path(in: canvas).boundingRect
    #expect(abs(bounds.minY - 4) < 0.5, "the pill floats 4 pt below the top edge")
    #expect(abs(bounds.height - 32) < 0.5)
    #expect(abs(bounds.width - 120) < 0.5)
    #expect(abs(bounds.midX - canvas.midX) < 0.5)
}

@Test func pillEndsAreRoundTopAndBottom() {
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let path = NotchShape(pillCapsule).path(in: canvas)
    let left = canvas.midX - 60, right = canvas.midX + 60
    let top: CGFloat = 4, bottom: CGFloat = 36
    // 2 pt in from each corner: inside a square corner, outside a 16 pt round one.
    for corner in [CGPoint(x: left + 2, y: top + 2), CGPoint(x: right - 2, y: top + 2),
                   CGPoint(x: left + 2, y: bottom - 2), CGPoint(x: right - 2, y: bottom - 2)] {
        #expect(!path.contains(corner), "\(corner) should be cut away by a round end")
    }
    #expect(path.contains(CGPoint(x: left + 1, y: top + 16)), "the end's widest point reaches the edge")
    #expect(path.contains(CGPoint(x: canvas.midX, y: top + 1)), "the top edge is straight between the ends")
}

/// A pill has nothing to blend into: an outer fillet left in its
/// parameters must not flare it wider.
@Test func pillIgnoresOuterFillets() {
    var flared = pillCapsule
    flared.outerFillet = 6
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    #expect(abs(NotchShape(flared).path(in: canvas).boundingRect.width - 120) < 0.5)
}

/// The point a hidden pill shrinks into draws nothing.
@Test func aZeroSizedPillCoversNothing() {
    let point = NotchShapeParameters(width: 0, height: 0, bottomRadius: 16, outerFillet: 0, topInset: 4, topRadius: 16)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let path = NotchShape(point).path(in: canvas)
    #expect(path.boundingRect.width < 0.5 && path.boundingRect.height < 0.5)
    #expect(!path.contains(CGPoint(x: canvas.midX, y: 4)))
}

/// Mid-growth the two ends share the height: neither radius may pass half
/// of it, so a short pill is rounded top AND bottom, not square on top.
@Test func pillRadiiShareTheHeight() {
    let small = NotchShapeParameters(width: 40, height: 10, bottomRadius: 16, outerFillet: 0, topInset: 4, topRadius: 16)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let path = NotchShape(small).path(in: canvas)
    let left = canvas.midX - 20, top: CGFloat = 4, bottom: CGFloat = 14
    #expect(abs(path.boundingRect.height - 10) < 0.5)
    #expect(!path.contains(CGPoint(x: left + 0.5, y: top + 0.5)), "the top end is rounded too")
    #expect(!path.contains(CGPoint(x: left + 0.5, y: bottom - 0.5)))
}

@Test func pillValuesInterpolateAndRoundTrip() {
    let point = NotchShapeParameters(width: 0, height: 0, bottomRadius: 16, outerFillet: 0, topInset: 4, topRadius: 16)
    let mid = NotchShapeParameters.lerp(point, pillCapsule, 0.5)
    #expect(mid.topInset == 4)
    #expect(mid.topRadius == 16)
    #expect(mid.width == 60)

    var p = pillCapsule
    let captured = p.animatableData
    p.topInset = 0; p.topRadius = 0
    p.animatableData = captured
    #expect(p.topInset == 4)
    #expect(p.topRadius == 16)
}

// MARK: - Sizes on a real notch never change (2026-10-21)

/// Every resting size on the measured notch and on a scaled mode's wider,
/// taller one, exactly as before the pill: it must not move a MacBook by a
/// point. One deliberate change since (2026-10-21): a scaled mode's plain
/// blip is the notch plus two 38 pt ears, 284 pt, not the measured notch's
/// 255, which left it 23.5 pt ears.
@Test func realNotchSizesAreExactlyAsBefore() {
    func p(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ f: CGFloat) -> NotchShapeParameters {
        NotchShapeParameters(width: w, height: h, bottomRadius: r, outerFillet: f)
    }
    let measured = NotchMetrics(notchRect: measuredNotch)
    #expect(measured.collapsed == p(179, 32, 9, 0))
    #expect(measured.retracted == p(179, 32, 9, 0))
    #expect(measured.peek == p(179, 38, 11, 4))
    #expect(measured.captioned(fitting: 300) == p(300, 58, 18, 9))
    #expect(measured.oneActivity == p(255, 32, 12, 6))
    #expect(measured.oneActivity(earWidth: 60) == p(299, 32, 12, 6))
    #expect(measured.expanded == p(356, 168, 26, 13))
    #expect(measured.expanded(outputRows: 2) == p(356, 238, 26, 13))
    #expect(measured.expanded(outputRows: 2, earsShowing: true) == p(356, 238, 26, 13))
    #expect(measured.cardTopBand(earsShowing: false) == 32)
    #expect(measured.cardTopBand(earsShowing: true) == 32)

    let scaled = NotchMetrics(notchRect: CGRect(x: 751, y: 0, width: 208, height: 37))
    #expect(scaled.collapsed == p(208, 37, 9, 0))
    #expect(scaled.peek == p(208, 43, 11, 4))
    #expect(scaled.captioned(fitting: 300) == p(300, 63, 18, 9))
    #expect(scaled.oneActivity == p(284, 37, 12, 6))
    #expect(scaled.oneActivity(earWidth: 60) == p(328, 37, 12, 6))
    #expect(scaled.earWidth(forIslandWidth: scaled.oneActivity.width) == NotchMetrics.activityEarWidth)
    #expect(scaled.expanded == p(356, 168, 26, 13))
    #expect(scaled.cardTopBand(earsShowing: false) == 37)
}

// MARK: - The pill's sizes (2026-10-21)

private let pillHole = CGRect(x: 938, y: 0, width: 44, height: 32)

@Test func pillSizesFollowTheSpec() {
    func pill(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NotchShapeParameters {
        NotchShapeParameters(width: w, height: h, bottomRadius: r, outerFillet: 0, topInset: 4, topRadius: r)
    }
    let m = NotchMetrics(notchRect: pillHole, isVirtual: true)
    #expect(m.retracted == pill(0, 0, 16), "hidden: a point at the top centre")
    #expect(m.collapsed == pill(120, 32, 16), "the resting footprint: 44 pt middle, two 38 pt ears")
    #expect(m.peek == m.collapsed, "an empty pill acknowledges the hover")
    #expect(m.oneActivity == pill(120, 32, 16))
    #expect(m.oneActivity(earWidth: 60) == pill(164, 32, 16), "a long Focus name still stretches it")
    #expect(m.captioned(fitting: 300) == pill(300, 58, 18))
    #expect(m.captioned(fitting: 100).width == NotchMetrics.captionedMinimumWidth)
    #expect(m.expanded == pill(356, 148, 26), "the card without its top strip")
    #expect(m.expanded(outputRows: 2) == pill(356, 218, 26))
}

/// The strip comes back while the ears have something to show, output
/// list or not, and the content area stays 136 pt either way.
@Test func pillCardGrowsItsStripOnlyWhileTheEarsShowSomething() {
    let m = NotchMetrics(notchRect: pillHole, isVirtual: true)
    #expect(m.cardTopBand(earsShowing: false) == 12)
    #expect(m.cardTopBand(earsShowing: true) == 32)
    #expect(m.expanded(outputRows: 0, earsShowing: true).height == 168)
    #expect(m.expanded(outputRows: 2, earsShowing: true).height == 238)
    for ears in [false, true] {
        #expect(m.expanded(outputRows: 0, earsShowing: ears).height - m.cardTopBand(earsShowing: ears) == 136)
    }
}

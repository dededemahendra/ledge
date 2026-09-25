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
    #expect(metrics.expanded.height == 118)
    #expect(metrics.expanded.bottomRadius == 26)
    #expect(metrics.expanded.outerFillet == 13)
}

@Test func earWidthLeavesRoomBesideTheHole() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect((metrics.oneActivity.width - 179) / 2 == 38)
    #expect((metrics.twoActivities.width - 179) / 2 == 81.5)
}

@Test func interpolationIsMonotonicAndBounded() {
    let a = NotchShapeParameters(width: 179, height: 32, bottomRadius: 9, outerFillet: 0)
    let b = NotchShapeParameters(width: 390, height: 118, bottomRadius: 26, outerFillet: 13)
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
    #expect(abs(bounds.height - 118) < 0.5)
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

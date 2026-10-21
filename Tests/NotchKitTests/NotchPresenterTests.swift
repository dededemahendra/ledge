import Testing
import CoreGraphics
@testable import NotchKit

// Fix-wave item 2: `refreshInteractiveRegion` (clicks) claimed a `NotchShape`
// path while `reevaluateHover` tested a plain `CGRect`. These tests exercise
// the two static, pure geometry helpers `NotchPresenter` now shares between
// them (`islandPath(for:)`/`localPoint(_:on:)`) directly — no real
// `NSScreen.islandHost`/`NSEvent.mouseLocation` needed, so they are fast and
// fully deterministic regardless of what hardware runs the suite.

/// Same shape as `NotchMetrics(notchRect: measuredNotch).expanded` used
/// elsewhere (`NotchShapeTests`), hardcoded here to keep this file decoupled
/// from `NotchMetrics`/notch-rect specifics — only the shape parameters
/// themselves matter for this geometry.
private let testParameters = NotchShapeParameters(width: 390, height: 168, bottomRadius: 26, outerFillet: 13)
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
/// local (126, 167) sits 1pt inside the naive rect's bottom-left corner —
/// comfortably inside the plain `width x height` box — but is outside the
/// circle rounding that corner (radius 26 centred at (151, 142) for the
/// 168pt-tall expanded card), so it is cut off by the actual path. Point
/// re-derived each time `expanded.height` moved (118 -> 140 -> 168); the
/// geometry argument is identical, just translated down with the corner.
@Test func roundedBottomCornerIsInsideTheNaiveRectButOutsideTheRealPath() {
    let global = CGPoint(
        x: testScreenFrame.midX + 126 - NotchPresenter.canvas.width / 2,
        y: testScreenFrame.maxY - 167
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

/// The canvas may take mouse events only while there is an island AND the
/// cursor is on it. A visible island the cursor is not on must stay
/// transparent, or the 640x320 canvas kills every click beneath it — the
/// 2026-09-28 "click the notch, then can't click anything" bug.
@Test func theCanvasTakesMouseEventsOnlyWhileTheCursorIsOnAVisibleIsland() {
    #expect(NotchPresenter.shouldAcceptMouse(visible: true, hovered: true))
    #expect(!NotchPresenter.shouldAcceptMouse(visible: true, hovered: false))
    #expect(!NotchPresenter.shouldAcceptMouse(visible: false, hovered: true), "no island, nothing to click")
    #expect(!NotchPresenter.shouldAcceptMouse(visible: false, hovered: false))
}

// MARK: - Hover zone (2026-10-21)

private let measuredNotchRect = CGRect(x: 645.5, y: 0, width: 179, height: 32)

/// The hidden pill is found at its resting footprint plus the margin, and
/// right up to the top edge over its 4 pt float (2026-10-21): a pointer
/// pushed against the top of the screen finds it, as it finds a notch.
@Test func aHiddenPillIsHoveredFromTheTopEdgeDown() {
    let metrics = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    let zone = NotchPresenter.hoverParameters(state: .hidden, drawn: metrics.retracted, metrics: metrics)
    #expect(zone.width == 128, "the 120 pt pill plus the 8 pt forgiveness")
    #expect(zone.height == 40, "32, the 4 pt forgiveness, and the 4 pt float")
    #expect(zone.topInset == 0)
    let path = NotchPresenter.islandPath(for: zone)
    #expect(path.contains(CGPoint(x: NotchPresenter.canvas.midX, y: 0.5)), "a pointer against the top edge")
}

@Test func thePillsHoverPreviewReachesTheTopEdgeToo() {
    let metrics = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    let zone = NotchPresenter.hoverParameters(state: .peek, drawn: metrics.peek, metrics: metrics)
    #expect(zone.topInset == 0)
    #expect(zone.height == 40)
}

@Test func aHiddenRealNotchIsHoveredAtTheNotchsSize() {
    let metrics = NotchMetrics(notchRect: measuredNotchRect)
    let zone = NotchPresenter.hoverParameters(state: .hidden, drawn: metrics.retracted, metrics: metrics)
    #expect(zone.width == 187, "the notch plus the 8pt forgiveness")
    #expect(zone.height == 36, "the notch plus the 4pt forgiveness")
}

/// On a real notch the big states are hovered exactly as drawn: its inset is 0.
@Test func aLiveIslandIsHoveredExactlyAsDrawn() {
    let metrics = NotchMetrics(notchRect: measuredNotchRect)
    #expect(NotchPresenter.hoverParameters(state: .activity, drawn: metrics.oneActivity, metrics: metrics) == metrics.oneActivity)
    #expect(NotchPresenter.hoverParameters(state: .expanded, drawn: metrics.expanded, metrics: metrics) == metrics.expanded)
}

/// A visible pill is found from the top edge down too (2026-10-21): the
/// zone reaches up over its float, as a notch's does.
@Test func aLivePillIsHoveredFromTheTopEdgeDown() {
    let metrics = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    for (state, drawn) in [(NotchState.activity, metrics.oneActivity), (.expanded, metrics.expanded)] {
        let zone = NotchPresenter.hoverParameters(state: state, drawn: drawn, metrics: metrics)
        #expect(zone.width == drawn.width)
        #expect(zone.height == drawn.height + 4)
        #expect(zone.topInset == 0)
        #expect(NotchPresenter.islandPath(for: zone).contains(CGPoint(x: NotchPresenter.canvas.midX, y: 0.5)))
    }
}

// MARK: - The lock screen (2026-10-21)

@Test func theWindowShowsWhileLockedOnlyWhenTheIslandMayBeThere() {
    #expect(NotchPresenter.shouldShowWindow(visible: true, locked: false, showsOnLockScreen: false))
    #expect(NotchPresenter.shouldShowWindow(visible: true, locked: true, showsOnLockScreen: true))
    #expect(!NotchPresenter.shouldShowWindow(visible: true, locked: true, showsOnLockScreen: false),
            "no space or the switch off: hidden while locked, as from 2026-10-01")
    #expect(!NotchPresenter.shouldShowWindow(visible: false, locked: false, showsOnLockScreen: true), "nothing to show")
    #expect(!NotchPresenter.shouldShowWindow(visible: false, locked: true, showsOnLockScreen: true))
}

/// A space whose calls do nothing: a presenter that may show on the lock
/// screen, without touching the real window server.
@MainActor
private func quietSpace() -> SkyLightSpace {
    SkyLightSpace(calls: .init(mainConnection: { 1 }, createSpace: { _ in 2 }, setAbsoluteLevel: { _, _, _ in },
                               showSpace: { _, _ in }, addWindow: { _, _, _ in }))
}

@MainActor
private func playing(_ p: NotchPresenter) {
    p.controller.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
    p.controller.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
}

@MainActor
@Test func withASpaceLockingKeepsTheIslandOutAndLookOnly() {
    let p = NotchPresenter(space: quietSpace())
    #expect(p.showsOnLockScreen)
    playing(p)
    p.setLocked(true)
    #expect(p.controller.isLocked)
    #expect(!p.controller.isTucked, "not tucked into the notch: it stays on the lock screen")
    #expect(p.controller.state == .activity)
    p.setLocked(false)
    #expect(!p.controller.isLocked && !p.controller.isTucked)
}

@MainActor
@Test func withoutASpaceLockingTucksAndHidesAsBefore() {
    let p = NotchPresenter(space: nil)
    #expect(!p.showsOnLockScreen)
    playing(p)
    p.setLocked(true)
    #expect(p.controller.isLocked && p.controller.isTucked, "tucked and hidden while locked, the 2026-10-01 behaviour")
}

@MainActor
@Test func theSwitchFlippedWhileLockedHidesOrShowsTheIslandAtOnce() {
    let p = NotchPresenter(space: quietSpace())
    playing(p)
    p.setLocked(true)
    p.setShowsOnLockScreen(false)
    #expect(!p.showsOnLockScreen && p.controller.isTucked)
    p.setShowsOnLockScreen(true)
    #expect(p.showsOnLockScreen && !p.controller.isTucked)
}

/// Review Focus 3: unlocking under a card the pointer opened keeps it open,
/// controls back, with no tuck and so no collapse or pop.
@MainActor
@Test func unlockingWithTheCardOpenKeepsItOpenAndUntucked() {
    let p = NotchPresenter(space: quietSpace())
    playing(p)
    p.controller.setHovered(true)
    #expect(p.controller.state == .expanded)
    p.setLocked(true)
    #expect(p.controller.state == .expanded)
    p.setLocked(false)
    #expect(p.controller.state == .expanded && !p.controller.isTucked && !p.controller.isLocked)
}

/// Review Focus 4: a two-finger swipe over the locked island with music
/// playing skips nothing and shows no skip glyph.
@MainActor
@Test func aSwipeOnTheLockedIslandSkipsNothing() {
    let p = NotchPresenter(space: quietSpace())
    var intents: [NotchIntent] = []
    p.controller.onIntent = { intents.append($0) }
    playing(p)
    p.setLocked(true)
    p.handleSwipe(deltaX: 0, phase: .began, invertedFromDevice: true)
    p.handleSwipe(deltaX: -60, phase: .changed, invertedFromDevice: true)
    #expect(intents.isEmpty)
    #expect(p.controller.skipHint == nil, "no skip glyph while locked")
}

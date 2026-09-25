import Testing
import AppKit
import CoreGraphics
@testable import NotchKit

// AppKit refuses to construct a real `NSPanel` inside a test bundle until the
// application object exists. `NSApplication.shared` is idempotent — safe to
// call from every test that constructs a window, regardless of test order.
@MainActor
private func ensureApplication() {
    _ = NSApplication.shared
}

@MainActor
private func makeWindow() throws -> NotchWindow {
    ensureApplication()
    let screen = try #require(NSScreen.main, "tests need a display")
    return NotchWindow(screen: screen)
}

@MainActor
@Test func windowIsAnInvisibleNonActivatingOverlay() throws {
    let w = try makeWindow()
    #expect(w.level.rawValue == NSWindow.Level.statusBar.rawValue + 1)
    #expect(w.isOpaque == false)
    #expect(w.hasShadow == false)
    #expect(w.backgroundColor == .clear)
    #expect(w.isMovable == false)
    #expect(w.hidesOnDeactivate == false)
    #expect(w.isFloatingPanel)
    #expect(w.styleMask.contains(.borderless))
    #expect(w.styleMask.contains(.nonactivatingPanel))
}

@MainActor
@Test func windowFollowsSpacesAndSurvivesFullscreen() throws {
    let w = try makeWindow()
    #expect(w.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(w.collectionBehavior.contains(.stationary))
    #expect(w.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(w.collectionBehavior.contains(.ignoresCycle))
}

@MainActor
@Test func canvasIsTheFixedOversizedSize() throws {
    let w = try makeWindow()
    #expect(w.frame.width == NotchMetrics.canvasSize.width)
    #expect(w.frame.height == NotchMetrics.canvasSize.height)
}

@MainActor
@Test func canvasIsAnchoredToTheTopCentreOfItsScreen() throws {
    ensureApplication()
    let screen = try #require(NSScreen.main)
    let w = NotchWindow(screen: screen)
    #expect(abs(w.frame.midX - screen.frame.midX) < 1)
    #expect(abs(w.frame.maxY - screen.frame.maxY) < 1)
}

@MainActor
@Test func lockedStateRaisesAboveTheShield() throws {
    let w = try makeWindow()
    w.setLocked(true)
    #expect(w.level.rawValue == Int(CGShieldingWindowLevel()) + 1)
    w.setLocked(false)
    #expect(w.level.rawValue == NSWindow.Level.statusBar.rawValue + 1)
}

// --- hit testing: Review Focus 4 ---

@MainActor
@Test func noPathMeansTheWindowClaimsNothing() throws {
    let w = try makeWindow()
    w.interactivePath = nil
    let centre = CGPoint(x: w.frame.width / 2, y: w.frame.height / 2)
    #expect(w.hostingView.hitTest(centre) == nil,
            "a hidden island must never swallow a click")
}

@MainActor
@Test func pointsInsideThePathAreClaimedAndOutsideAreNot() throws {
    let w = try makeWindow()
    let box = CGRect(x: 100, y: 100, width: 200, height: 40)
    w.interactivePath = CGPath(rect: box, transform: nil)
    #expect(w.hostingView.hitTest(CGPoint(x: 200, y: 120)) != nil)
    #expect(w.hostingView.hitTest(CGPoint(x: 10, y: 10)) == nil)
    #expect(w.hostingView.hitTest(CGPoint(x: 200, y: 300)) == nil)
}

// Review Focus 1: repositioning must not leave a stale claim.
@MainActor
@Test func repositioningClearsTheStaleInteractivePath() throws {
    ensureApplication()
    let screen = try #require(NSScreen.main)
    let w = NotchWindow(screen: screen)
    w.interactivePath = CGPath(rect: CGRect(x: 0, y: 0, width: 600, height: 300), transform: nil)
    w.reposition(for: screen)
    #expect(w.interactivePath == nil,
            "a path from the previous geometry would claim clicks in the wrong place")
    #expect(w.hostingView.hitTest(CGPoint(x: 300, y: 150)) == nil)
}

@MainActor
@Test func notchShapePathClaimsTheIslandAndNotTheMenuBarBesideIt() throws {
    let w = try makeWindow()
    let metrics = NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32))
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    w.setInteractiveShape(NotchShape(metrics.collapsed), in: canvas)

    // In view coordinates the island hangs from the top edge of the canvas.
    let insideIsland = CGPoint(x: canvas.midX, y: canvas.maxY - 16)
    let besideIsland = CGPoint(x: canvas.midX - 200, y: canvas.maxY - 16)
    #expect(w.hostingView.hitTest(insideIsland) != nil)
    #expect(w.hostingView.hitTest(besideIsland) == nil,
            "menu bar clicks beside the notch must pass through")
}

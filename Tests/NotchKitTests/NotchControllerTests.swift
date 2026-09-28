import Testing
import CoreGraphics
@testable import NotchKit

@MainActor
private func makeController(reduceMotion: Bool = false) -> NotchController {
    NotchController(
        metrics: NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32)),
        reduceMotion: reduceMotion
    )
}

@MainActor
@Test func startsHiddenAndInvisible() {
    let c = makeController()
    #expect(c.state == .hidden)
    #expect(c.isVisible == false)
}

@MainActor
@Test func hoverPeeksAndUnhoverHides() {
    let c = makeController()
    c.setHovered(true)
    #expect(c.state == .peek)
    #expect(c.isVisible)
    c.setHovered(false)
    #expect(c.state == .hidden)
}

@MainActor
@Test func clickExpandsAndDismissCollapses() {
    let c = makeController()
    c.setHovered(true)
    c.click()
    #expect(c.state == .expanded)
    c.dismiss()
    #expect(c.state == .peek, "cursor is still over the island after dismissing")
    c.setHovered(false)
    #expect(c.state == .hidden)
}

@MainActor
@Test func expandedSurvivesTheCursorLeaving() {
    let c = makeController()
    c.setHovered(true)
    c.click()
    c.setHovered(false)
    #expect(c.state == .expanded, "an opened panel must not close just because the cursor left")
}

@MainActor
private func someMedia() -> MediaPresentation {
    MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200)
}

// MARK: - Hover opens the panel (2026-09-28: hover, not click)

@MainActor
@Test func hoverOpensThePanelWhenThereIsMediaAndLeavingClosesIt() {
    let c = makeController()
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.state == .activity)
    c.setHovered(true)
    #expect(c.state == .expanded)
    #expect(!c.isPinnedOpen, "hover-opened, not pinned")
    c.setHovered(false)
    #expect(c.state == .activity, "the cursor leaving closes a hover-opened panel")
}

@MainActor
@Test func hoverWithoutMediaOnlyPeeksOrKeepsTheActivity() {
    let c = makeController()
    c.setHovered(true)
    #expect(c.state == .peek, "nothing to open a panel for")
    c.setActivities([.init(id: "hud", title: "Sound", symbolName: "speaker.wave.3.fill", barFill: 0.4)], overflow: 0)
    #expect(c.state == .activity, "a lone HUD says everything in its ears; hover must not balloon it")
}

@MainActor
@Test func mediaArrivingOrLeavingUnderAParkedCursorOpensAndClosesThePanel() {
    let c = makeController()
    c.setHovered(true)
    #expect(c.state == .peek)
    c.setMedia(someMedia())
    #expect(c.state == .expanded, "media appearing under the cursor opens the panel")
    c.setMedia(nil)
    #expect(c.state == .peek, "media going away closes a hover-opened panel")
}

@MainActor
@Test func aPinnedPanelIgnoresHoverAndAHoverOpenedOneDoesNot() {
    let c = makeController()
    c.setMedia(someMedia())
    c.setHovered(true)
    c.click()
    #expect(c.isPinnedOpen)
    c.setHovered(false)
    #expect(c.state == .expanded, "pinned by click: survives the cursor leaving")
    c.dismiss()
    #expect(!c.isPinnedOpen)
    #expect(c.state == .hidden)

    c.setHovered(true)
    #expect(c.state == .expanded)
    c.dismiss()
    #expect(c.state == .expanded, "dismiss unpins, but the cursor still being there re-opens it")
    #expect(!c.isPinnedOpen)
    c.setHovered(false)
    #expect(c.state == .hidden)
}

@MainActor
@Test func activityShowsWithoutHoverAndRestsOnActivityState() {
    let c = makeController()
    c.setActivityCount(1)
    #expect(c.state == .activity)
    #expect(c.isVisible)
    c.setActivityCount(0)
    #expect(c.state == .hidden)
}

@MainActor
@Test func activityArrivingWhileExpandedDoesNotCollapseThePanel() {
    let c = makeController()
    c.setHovered(true)
    c.click()
    c.setActivityCount(2)
    #expect(c.state == .expanded)
}

@MainActor
@Test func hoverOverAnActivityPeeksButKeepsTheActivityVisible() {
    let c = makeController()
    c.setActivityCount(1)
    c.setHovered(true)
    #expect(c.state == .activity, "hover must not shrink a live activity to peek size")
    #expect(c.isVisible)
}

@MainActor
@Test func lastActivityDisappearingWhileHoveredFallsBackToPeek() {
    let c = makeController()
    c.setActivityCount(1)
    c.setHovered(true)
    c.setActivityCount(0)
    #expect(c.state == .peek)
}

@MainActor
@Test func parametersTrackTheState() {
    let c = makeController()
    #expect(c.parameters == c.metrics.collapsed)
    c.setHovered(true)
    #expect(c.parameters == c.metrics.peek)
    c.setActivityCount(1)
    #expect(c.parameters == c.metrics.oneActivity)
    c.setActivityCount(2)
    #expect(c.parameters == c.metrics.twoActivities)
    c.setActivityCount(5)
    #expect(c.parameters == c.metrics.twoActivities, "three or more still uses the two-slot size")
    c.click()
    #expect(c.parameters == c.metrics.expanded)
}

/// A LEADING volume/brightness HUD always gets the HUD island — alone, with a
/// sticky media activity behind it (every volume press while music plays),
/// or with overflow. Any other leading activity keeps the usual sizes.
@MainActor
@Test func aLeadingHUDActivityGetsTheHUDSizeWhateverIsBehindIt() {
    let c = makeController()
    let hud = NotchController.ActivityDisplay(id: "hud", title: "Sound", symbolName: "speaker.wave.3.fill", barFill: 0.4)
    c.setActivities([hud], overflow: 0)
    #expect(c.isHUDLeading)
    #expect(c.parameters == c.metrics.hud)

    c.setActivities([.init(id: "power", title: "Charging · 42%", compactText: "42%")], overflow: 0)
    #expect(!c.isHUDLeading)
    #expect(c.parameters == c.metrics.oneActivity)

    c.setActivities([hud, .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.isHUDLeading)
    #expect(c.parameters == c.metrics.hud, "a volume press with music playing is still just the HUD")

    c.setActivities([hud], overflow: 1)
    #expect(c.parameters == c.metrics.hud, "overflow does not demote a live HUD either")

    c.setActivities([.init(id: "media", title: "Song", detail: "Artist"), .init(id: "power", title: "On AC", compactText: "95%")], overflow: 0)
    #expect(!c.isHUDLeading)
    #expect(c.parameters == c.metrics.twoActivities)
}

// Review Focus 1: geometry can change under a live island.
@MainActor
@Test func changingMetricsUpdatesParametersImmediately() {
    let c = makeController()
    c.setHovered(true)
    c.click()
    #expect(c.parameters == c.metrics.expanded)
    c.metrics = NotchMetrics(notchRect: CGRect(x: 751, y: 0, width: 208, height: 37))
    #expect(c.parameters.height == 168, "expanded target is fixed by the spec")
    #expect(c.metrics.collapsed.width == 208, "collapsed follows the new hardware geometry")
}

@MainActor
@Test func reduceMotionIsReportedSoTheViewCanSwapTheAnimation() {
    #expect(makeController(reduceMotion: false).reduceMotion == false)
    #expect(makeController(reduceMotion: true).reduceMotion)
}

@MainActor
@Test func dismissFromHiddenIsANoOp() {
    let c = makeController()
    c.dismiss()
    #expect(c.state == .hidden)
}

@MainActor
@Test func clickWithoutHoverStillExpands() {
    // A click can arrive from a hit test without a preceding hover event.
    let c = makeController()
    c.click()
    #expect(c.state == .expanded)
}

@MainActor
@Test func clickDoesNothingWithoutAnIsland() {
    // On a Mac with no notch (or mid display-hot-plug gap), metrics carries
    // a zero notch rect. Without this guard, the menu bar's "Toggle Panel"
    // latches `state = .expanded` with no window ever created to show it,
    // and `recomputeState()` early-returns on `.expanded` forever after —
    // hover becomes permanently inert until Toggle Panel is pressed again.
    let c = NotchController(metrics: NotchMetrics(notchRect: .zero))
    c.click()
    #expect(c.state == .hidden)
}

// `dismiss()` re-derives rather than assigning `.hidden`, so it has three
// reachable outcomes. All three are pinned here: without these, a `dismiss()`
// rewritten as `state = isHovered ? .peek : .hidden` — silently dropping the
// activity fallback — would pass the whole suite.

@MainActor
@Test func dismissWithALiveActivityLandsOnActivity() {
    let c = makeController()
    c.setHovered(true)
    c.setActivityCount(1)
    c.click()
    #expect(c.state == .expanded)
    c.dismiss()
    #expect(c.state == .activity, "a live activity outranks hover once the panel closes")
}

@MainActor
@Test func dismissWithNothingToFallBackToLandsOnHidden() {
    let c = makeController()
    c.click()                     // hover never set, no activities
    c.dismiss()
    #expect(c.state == .hidden)
}

@MainActor
@Test func activityCountNeverGoesNegative() {
    let c = makeController()
    c.setActivityCount(-5)
    #expect(c.activityCount == 0)
    #expect(c.state == .hidden)
}

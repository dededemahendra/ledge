import Testing
import Foundation
import CoreGraphics
import AppKit
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
    c.setMedia(someMedia())
    c.click()
    #expect(c.state == .expanded)
    c.dismiss()
    #expect(c.state == .hidden)
}

@MainActor
@Test func expandedSurvivesTheCursorLeaving() {
    let c = makeController()
    c.setMedia(someMedia())
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

/// A tap on the island under the hover model: never pins what hover already
/// holds open, unpins what a click pinned, and opens nothing when there is
/// nothing to show.
@MainActor
@Test func tapNeverPinsAHoverOpenedPanelButPinsAndUnpinsOtherwise() {
    let c = makeController()
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)

    c.setHovered(true)
    #expect(c.state == .expanded && !c.isPinnedOpen)
    c.tap()
    #expect(!c.isPinnedOpen, "a click on the body of a hover-opened panel is not a request to pin it")
    c.setHovered(false)
    #expect(c.state == .activity, "…so leaving still closes it")

    c.tap()
    #expect(c.state == .expanded && c.isPinnedOpen, "a click on the compact island pins the panel open")
    c.tap()
    #expect(!c.isPinnedOpen, "a second click unpins")
    #expect(c.state == .activity)

    let empty = makeController()
    empty.setHovered(true)
    #expect(empty.state == .peek)
    empty.tap()
    #expect(empty.state == .peek, "nothing to show — a click must not open an empty slab")
}

/// A device blip never grows the island: alone it is the one-activity
/// island; over music it is STILL the one-activity island (artwork left,
/// device icon right), never the two-slot layout.
@MainActor
@Test func aLeadingDeviceActivityKeepsTheCompactIslandEvenOverMusic() {
    let c = makeController()
    let device = NotchController.ActivityDisplay(id: "device", title: "External Headphones", symbolName: "headphones")
    c.setActivities([device], overflow: 0)
    #expect(c.isDeviceLeading)
    #expect(c.parameters == c.metrics.oneActivity)

    c.setMedia(someMedia())
    c.setActivities([device, .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.isDeviceLeading)
    #expect(c.parameters == c.metrics.oneActivity, "headphones plugged in while music plays is an ear swap, not a slab")
}

/// Power keeps the plain one-activity island — glyph left, percentage right,
/// no words — alone or over music; never the two-slot layout.
@MainActor
@Test func aLeadingPowerActivityKeepsTheCompactIslandEvenOverMusic() {
    let c = makeController()
    let power = NotchController.ActivityDisplay(id: "power", title: "Charging · 95% · 20 min to full", compactText: "95%", symbolName: "bolt.fill")
    c.setActivities([power], overflow: 0)
    #expect(c.isPowerLeading)
    #expect(c.parameters == c.metrics.oneActivity)

    c.setMedia(someMedia())
    c.setActivities([power, .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.parameters == c.metrics.oneActivity, "plugging in while music plays is glyph + percent, not the two-slot layout")
}

@MainActor
@Test func outputsAreStoredForThePanelAndSelectOutputEmitsAnIntent() {
    let c = makeController()
    #expect(c.outputs.isEmpty)
    let options = [
        OutputOption(id: "builtin", name: "MacBook Air Speakers", symbolName: "laptopcomputer", isCurrent: true),
        OutputOption(id: "bt-1", name: "AirPods Pro", symbolName: "airpods.pro", isCurrent: false),
    ]
    c.setOutputs(options)
    #expect(c.outputs == options)

    var received: NotchIntent?
    c.onIntent = { received = $0 }
    c.emit(.selectOutput(id: "bt-1"))
    #expect(received == .selectOutput(id: "bt-1"))
    c.emit(.openSource)
    #expect(received == .openSource)
    c.emit(.toggleFavorite)
    #expect(received == .toggleFavorite)
}

/// The picker's open state sizes the island, so it lives in the controller:
/// only openable at `.expanded` with two or more outputs, and it closes
/// itself when the panel closes.
@MainActor
@Test func outputPickerOpensOnlyOnAnOpenPanelAndClosesWithIt() {
    let c = makeController()
    c.setMedia(someMedia())
    c.setOutputs([
        OutputOption(id: "builtin", name: "MacBook Air Speakers", symbolName: "laptopcomputer", isCurrent: true),
        OutputOption(id: "bt-1", name: "AirPods Pro", symbolName: "airpods.pro", isCurrent: false),
    ])
    c.setOutputPicker(open: true)
    #expect(!c.isOutputPickerOpen, "no panel, no picker")

    c.setHovered(true)
    #expect(c.state == .expanded)
    c.setOutputPicker(open: true)
    #expect(c.isOutputPickerOpen)
    #expect(c.parameters == c.metrics.expanded(outputRows: 2), "the island grows by two rows")

    c.setHovered(false)
    #expect(c.state != .expanded && !c.isOutputPickerOpen, "closing the panel closes the picker")
    #expect(c.parameters != c.metrics.expanded(outputRows: 2))

    c.setHovered(true)
    c.setOutputPicker(open: true)
    c.setOutputs([OutputOption(id: "builtin", name: "MacBook Air Speakers", symbolName: "laptopcomputer", isCurrent: true)])
    #expect(!c.isOutputPickerOpen, "one output is not a choice")
}

// MARK: - Blip pulse (2026-09-29)

/// The island pulses for a blip that lands WITHOUT a shape change (the
/// growth spring covers the other case), and again when a new blip
/// replaces it — plug then unplug, or a different kind.
@MainActor
@Test func aBlipLandingOnAnUnchangedIslandPulsesAndAShapeChangeDoesNot() {
    let c = makeController()
    let power = NotchController.ActivityDisplay(id: "power", title: "Charging · 95%", compactText: "95%", symbolName: "bolt.fill")
    c.setActivities([power], overflow: 0)
    #expect(c.blipPulse == 0, "from the bare notch the island grows — the spring announces it")

    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.blipPulse == 0, "media is not a blip")

    c.setActivities([power, .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.blipPulse == 1, "the charger over music: same island size, so pulse")

    c.setActivities([power, .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.blipPulse == 1, "the same blip re-published (TTL refresh) is not a new arrival")

    let unplugged = NotchController.ActivityDisplay(id: "power", title: "On battery · 95%", compactText: "95%", symbolName: "battery.100percent")
    c.setActivities([unplugged, .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.blipPulse == 2, "unplug replaces plug: a new blip, same id")

    let hud = NotchController.ActivityDisplay(id: "hud", title: "Sound", compactText: "50%", symbolName: "speaker.wave.3.fill", barFill: 0.5)
    c.setActivities([hud, .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.blipPulse == 3)
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "55%", symbolName: "speaker.wave.3.fill", barFill: 0.55),
                     .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.blipPulse == 3, "a volume step is the same blip; the value bump handles presses")
}

// MARK: - Song-change caption and swipe feedback (2026-09-29)

@MainActor
@Test func aCaptionGrowsTheIslandOnlyWhileMediaLeadsAtActivitySize() {
    let c = makeController()
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.setCaption("Song · Artist")
    #expect(c.hasCaption)
    #expect(c.parameters.height == c.metrics.captioned.height && c.parameters.width >= NotchMetrics.captionedMinimumWidth)

    c.setActivities([.init(id: "hud", title: "Sound", compactText: "50%", symbolName: "speaker.wave.3.fill", barFill: 0.5),
                     .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(!c.hasCaption, "a blip owns the island whole")
    #expect(c.parameters == c.metrics.oneActivity)

    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.hasCaption, "…and the caption is back once the blip expires, if still set")

    c.setHovered(true)
    #expect(c.state == .expanded && !c.hasCaption, "the panel already says it")
    c.setHovered(false)
    c.setCaption(nil)
    #expect(!c.hasCaption && c.parameters == c.metrics.oneActivity)
}

@MainActor
@Test func skipHintIsPlainStateTheEarReads() {
    let c = makeController()
    #expect(c.skipHint == nil)
    c.setSkipHint(.next)
    #expect(c.skipHint == .next)
    c.setSkipHint(nil)
    #expect(c.skipHint == nil)
    #expect(NotchController.skipHintDuration < NotchController.captionDuration, "a hint is a beat, a caption is a moment")
}

// MARK: - Lock screen (spec §7)

@MainActor
/// Locking changes nothing about the state (2026-10-01): the presenter
/// hides the window while locked and shows it again as it was, so an
/// unlock never plays a collapse the user did not ask for.
@Test func lockingLeavesTheStateAloneAndUnlockingRestoresIt() {
    let c = makeController()
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.state == .activity)

    c.setLocked(true)
    #expect(c.isLocked)
    #expect(c.state == .activity, "no card is forced open on the lock screen — macOS never shows it")
    #expect(!c.isPinnedOpen)

    c.setLocked(false)
    #expect(c.state == .activity)
}

@MainActor
@Test func lockingWithNothingPlayingShowsNothingExtra() {
    let c = makeController()
    c.setLocked(true)
    #expect(c.state == .hidden, "no media, no activity — an empty slab on the lock screen would be noise")

    c.setActivities([.init(id: "power", title: "Charging · 42%", compactText: "42%", symbolName: "bolt.fill")], overflow: 0)
    #expect(c.state == .activity, "charging state still shows in the ears while locked")
    #expect(c.parameters == c.metrics.oneActivity)
}

@MainActor
@Test func aPinnedPanelSurvivesLockAndUnlock() {
    let c = makeController()
    c.setMedia(someMedia())
    c.click()
    c.setLocked(true)
    c.setLocked(false)
    #expect(c.state == .expanded && c.isPinnedOpen)
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
    c.setMedia(someMedia())
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
    #expect(c.parameters == c.metrics.oneActivity, "more activities never grow the island; they queue")
    c.setActivityCount(5)
    #expect(c.parameters == c.metrics.oneActivity)
    c.setMedia(someMedia())
    c.click()
    #expect(c.parameters == c.metrics.expanded)
}

/// A LEADING volume/brightness HUD always keeps the one-activity island —
/// alone, with a sticky media activity behind it (every volume press while
/// music plays), or with overflow — as does every other leading activity.
@MainActor
@Test func aLeadingHUDActivityKeepsTheCompactIslandWhateverIsBehindIt() {
    let c = makeController()
    let hud = NotchController.ActivityDisplay(id: "hud", title: "Sound", symbolName: "speaker.wave.3.fill", barFill: 0.4)
    c.setActivities([hud], overflow: 0)
    #expect(c.isHUDLeading)
    #expect(c.parameters == c.metrics.oneActivity)

    c.setActivities([.init(id: "notification", title: "Mail · 3 new", compactText: "3")], overflow: 0)
    #expect(!c.isHUDLeading)
    #expect(c.parameters == c.metrics.oneActivity)

    c.setActivities([hud, .init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.isHUDLeading)
    #expect(c.parameters == c.metrics.oneActivity, "a volume press with music playing is still just the HUD")

    c.setActivities([hud], overflow: 1)
    #expect(c.parameters == c.metrics.oneActivity, "overflow does not demote a live HUD either")

    c.setActivities([.init(id: "media", title: "Song", detail: "Artist"), .init(id: "power", title: "On AC", compactText: "95%")], overflow: 0)
    #expect(!c.isHUDLeading)
    #expect(c.parameters == c.metrics.oneActivity)
}

// Review Focus 1: geometry can change under a live island.
@MainActor
@Test func changingMetricsUpdatesParametersImmediately() {
    let c = makeController()
    c.setMedia(someMedia())
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
    c.setMedia(someMedia())
    c.click()
    #expect(c.state == .expanded)
}

/// The expanded panel is only ever the now-playing card (2026-09-29): a
/// click on a lone blip must not pin open the old title-and-bar slab.
@MainActor
@Test func clickWithoutACardDoesNothing() {
    let c = makeController()
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")], overflow: 0)
    c.click()
    #expect(c.state == .activity && !c.isPinnedOpen)
    c.tap()
    #expect(c.state == .activity && !c.isPinnedOpen, "nor via a tap")
}

@MainActor
@Test func clickDoesNothingWithoutAnIsland() {
    // On a Mac with no notch (or mid display-hot-plug gap), metrics carries
    // a zero notch rect. Without this guard, the menu bar's "Toggle Panel"
    // latches `state = .expanded` with no window ever created to show it,
    // and `recomputeState()` early-returns on `.expanded` forever after —
    // hover becomes permanently inert until Toggle Panel is pressed again.
    let c = NotchController(metrics: NotchMetrics(notchRect: .zero))
    c.setMedia(someMedia())
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
    c.setMedia(someMedia())
    c.setActivityCount(1)
    c.click()
    #expect(c.state == .expanded)
    c.dismiss()
    #expect(c.state == .activity, "a live activity is what the island falls back to once the panel closes")
}

@MainActor
@Test func dismissWithNothingToFallBackToLandsOnHidden() {
    let c = makeController()
    c.setMedia(someMedia())
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

/// The player quitting (or crashing) takes the card with it; a panel pinned
/// on that card must not outlive it as an empty slab (2026-09-29). Nil-to-nil
/// media, though, is stream noise and must leave a live blip alone.
@MainActor
@Test func thePlayerQuittingReleasesAPinnedPanel() {
    // Production order: the app model drops the card, then republishes the
    // activities without the media one.
    let c = makeController()
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.tap()
    #expect(c.state == .expanded && c.isPinnedOpen)
    c.setMedia(nil)
    #expect(!c.isPinnedOpen, "a pin is a pin on the card; no card, no pin")
    c.setActivities([], overflow: 0)
    #expect(c.state == .hidden, "back to idle, not an empty slab")

    // A blip live at that moment: the island lands on the blip, not the panel.
    let d = makeController()
    d.setMedia(someMedia())
    d.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    d.tap()
    d.setMedia(nil)
    d.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")], overflow: 0)
    #expect(d.state == .activity && !d.isPinnedOpen)

    // Nil-to-nil media is stream noise: a live blip is left exactly as it was.
    let e = makeController()
    e.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")], overflow: 0)
    e.setMedia(nil)
    #expect(e.state == .activity && !e.isPinnedOpen)
}

/// A blip that carries a link — a meeting reminder's join URL — is a
/// button while it shows (2026-09-29): a tap opens it and never pins.
@MainActor
@Test func aBlipWithALinkOpensItOnTap() {
    let c = makeController()
    var opened: [NotchIntent] = []
    c.onIntent = { opened.append($0) }
    let url = URL(string: "https://meet.google.com/abc-defg-hij")!
    c.setMedia(someMedia())
    c.setActivities([.init(id: "calendar", title: "Standup", compactText: "5m", symbolName: "calendar", url: url)], overflow: 0)
    c.tap()
    #expect(opened == [.open(url)])
    #expect(c.state == .activity && !c.isPinnedOpen, "the link wins over pinning the card behind it")

    c.setActivities([.init(id: "power", title: "Battery", compactText: "42%", symbolName: "battery.100percent.bolt")], overflow: 0)
    c.tap()
    #expect(opened.count == 1, "a blip without a link is just a blip…")
    #expect(c.isPinnedOpen, "…so the tap pins the card as usual")
}

/// With nothing playing and no blip live, hover previews the next event
/// in the meeting blip's own layout (2026-09-29); a tap joins.
@MainActor
@Test func hoverWithNothingPlayingPreviewsTheNextEvent() {
    let c = makeController()
    var opened: [NotchIntent] = []
    c.onIntent = { opened.append($0) }
    let url = URL(string: "https://zoom.us/j/1")!
    c.setUpcoming(UpcomingEvent(title: "Design review", compactText: "42m", caption: "Design review · 14:00", url: url))
    c.setHovered(true)
    #expect(c.state == .peek && c.isPreviewingUpcoming)
    #expect(c.parameters.height == c.metrics.captioned.height && c.parameters.width >= NotchMetrics.captionedMinimumWidth, "ears plus the caption line, like the reminder blip")
    #expect(c.captionText == "Design review · 14:00")
    #expect(c.linkURL == url, "the island is a button now — the view dips it on press")
    c.tap()
    #expect(opened == [.open(url)])
    #expect(c.state == .peek && !c.isPinnedOpen, "a tap joins; it never pins")
    c.setHovered(false)
    #expect(c.state == .hidden && !c.isPreviewingUpcoming)

    c.setActivityCount(1)
    c.setHovered(true)
    #expect(c.state == .activity && !c.isPreviewingUpcoming, "a live blip wins")
    c.setActivityCount(0)
    c.setMedia(someMedia())
    #expect(c.state == .expanded && !c.isPreviewingUpcoming, "the card wins")
    #expect(c.linkURL == nil, "the panel's own buttons take clicks at .expanded")
    c.setMedia(nil)
    c.setUpcoming(nil)
    #expect(c.state == .peek && c.parameters == c.metrics.peek, "nothing coming up: the plain peek")
}

/// A meeting blip carries its own caption; any other blip pre-empting the
/// island takes it whole (the media-only gate hid the reminder's title
/// until 2026-09-29).
@MainActor
@Test func aMeetingBlipCarriesItsCaptionButAHUDOverItDoesNot() {
    let c = makeController()
    let meeting = NotchController.ActivityDisplay(id: "calendar", title: "Standup", compactText: "5m", symbolName: "calendar")
    c.setActivities([meeting], overflow: 0)
    c.setCaption("Standup · 10:00")
    #expect(c.hasCaption && c.captionText == "Standup · 10:00")
    #expect(c.parameters.height == c.metrics.captioned.height && c.parameters.width >= NotchMetrics.captionedMinimumWidth)
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill"), meeting], overflow: 0)
    #expect(!c.hasCaption && c.parameters == c.metrics.oneActivity)
}

/// A long trailing text — a Focus's name where "On" was (2026-09-30) —
/// stretches the island to fit; the usual few characters leave it alone,
/// and a runaway text is capped rather than growing without end.
@MainActor
@Test func aLongTrailingTextWidensTheIslandAndAShortOneDoesNot() {
    let c = makeController()
    c.setActivities([.init(id: "focus", title: "Reduce Interruptions", compactText: "Reduce Interruptions", symbolName: "moon.fill")], overflow: 0)
    #expect(c.state == .activity)
    #expect(c.parameters.width > c.metrics.oneActivity.width, "wider than the 255 pt island")
    #expect(c.parameters.height == c.metrics.oneActivity.height, "…but no taller")
    #expect(c.parameters.width <= c.metrics.oneActivity(earWidth: NotchMetrics.activityEarMaximum).width)

    c.setActivities([.init(id: "focus", title: "Work", compactText: "Work", symbolName: "moon.fill")], overflow: 0)
    #expect(c.parameters == c.metrics.oneActivity, "four characters fit the default ear")
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "100%", symbolName: "speaker.wave.3.fill")], overflow: 0)
    #expect(c.parameters == c.metrics.oneActivity)

    c.setActivities([.init(id: "focus", title: "x", compactText: String(repeating: "Interruptions ", count: 6), symbolName: "moon.fill")], overflow: 0)
    #expect(c.parameters.width == c.metrics.oneActivity(earWidth: NotchMetrics.activityEarMaximum).width, "capped")
}

/// Modes of the open card (2026-09-30): a swipe moves between now-playing
/// and the calendar; on the preview it opens the calendar; leaving resets.
@MainActor
@Test func aSwipeMovesBetweenTheCardsModesAndOpensTheCalendarFromThePreview() {
    let c = makeController()
    let item = UpcomingEvent(title: "Standup", compactText: "42m", caption: "Standup · 10:00", time: "10:00", url: nil)
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.setHovered(true)
    #expect(c.state == .expanded && c.panel == .media)
    #expect(!c.swipe(.next), "one mode only: not taken, so the presenter skips the track")

    let month = CalendarModeData(monthTitle: "September 2026", monthShort: "SEP", weekdayTitle: "WED", dayNumber: 30, weekdaySymbols: ["S", "M", "T", "W", "T", "F", "S"], weeks: [[nil, nil, 1, 2, 3, 4, 5]], today: 30, markedDays: [30], items: [item])
    c.setCalendarMode(month)
    #expect(c.availablePanels == [.media, .calendar])
    #expect(c.swipe(.next) && c.panel == .calendar && c.state == .expanded)
    #expect(c.swipe(.next) && c.panel == .calendar, "at the last mode: taken, nothing moves, no skip")
    #expect(c.swipe(.previous) && c.panel == .media)
    c.setHovered(false)
    c.setHovered(true)
    _ = c.swipe(.next)
    c.setHovered(false)
    #expect(c.panel == .media, "leaving resets to now-playing")

    // Nothing playing: the preview swipes open into the calendar mode.
    let d = makeController()
    d.setUpcoming(item)
    d.setCalendarMode(month)
    d.setHovered(true)
    #expect(d.state == .peek && d.isPreviewingUpcoming)
    #expect(d.swipe(.next) && d.state == .expanded && d.panel == .calendar)
    #expect(d.parameters == d.metrics.expanded)
    d.setHovered(false)
    #expect(d.state == .hidden && d.panel == .media)
    d.setCalendarMode(nil)
    #expect(d.availablePanels.isEmpty)
}

/// The month grid (2026-09-30): rows of seven from the calendar's first
/// weekday, padded at both ends.
@Test func theMonthGridPadsToWholeWeeks() {
    var sundayFirst = Calendar(identifier: .gregorian)
    sundayFirst.firstWeekday = 1
    sundayFirst.timeZone = TimeZone(identifier: "UTC")!
    let sept30 = sundayFirst.date(from: DateComponents(year: 2026, month: 9, day: 30))!
    let weeks = MonthGrid.weeks(containing: sept30, calendar: sundayFirst)
    #expect(weeks.count == 5)
    #expect(weeks[0] == [nil, nil, 1, 2, 3, 4, 5], "September 2026 starts on a Tuesday")
    #expect(weeks[4] == [27, 28, 29, 30, nil, nil, nil])
    var mondayFirst = sundayFirst
    mondayFirst.firstWeekday = 2
    #expect(MonthGrid.weeks(containing: sept30, calendar: mondayFirst)[0] == [nil, 1, 2, 3, 4, 5, 6])
    let data = CalendarModeData(now: sept30, calendar: mondayFirst, markedDays: [1], items: [])
    #expect(data.today == 30 && data.weekdaySymbols.count == 7 && data.weekdaySymbols[0] == mondayFirst.veryShortStandaloneWeekdaySymbols[1])
    #expect(data.dayNumber == 30 && data.weekendColumns == [false, false, false, false, false, true, true], "Monday first: the weekend is the last two columns")
}

/// The caption island fits its line (2026-10-01): short lines keep the
/// floor, long ones widen up to the card's width, the row's height stays.
@MainActor
@Test func theCaptionIslandFitsItsLine() {
    let c = makeController()
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.setCaption("Hey · Sia")
    #expect(c.hasCaption)
    #expect(c.parameters.width == NotchMetrics.captionedMinimumWidth)
    #expect(c.parameters.height == c.metrics.captioned.height)
    c.setCaption("Somewhere Only We Know (Live at the Royal Albert Hall) · Keane")
    #expect(c.parameters.width > NotchMetrics.captionedMinimumWidth && c.parameters.width < NotchMetrics.captionedMaximumWidth)
    c.setCaption(String(repeating: "Supercalifragilistic ", count: 4) + "· Someone")
    #expect(c.parameters.width == NotchMetrics.captionedMaximumWidth, "capped at the card's width; the row truncates")
}

/// Tucked (2026-10-01): the bare notch whatever the state, the state
/// itself untouched — the lock tucks, the unlock untucks into the pop.
@MainActor
@Test func tuckingDrawsTheBareNotchWithoutChangingState() {
    let c = makeController()
    c.setActivityCount(1)
    #expect(c.parameters == c.metrics.oneActivity)
    c.setTucked(true)
    #expect(c.state == .activity && c.isVisible)
    #expect(c.parameters == c.metrics.collapsed)
    c.setTucked(false)
    #expect(c.parameters == c.metrics.oneActivity)
}

/// The captioned island must also fit its ears (2026-10-01: a "2h 20m"
/// countdown was cut at the 255 pt floor): a short line with a long
/// trailing text widens for the text.
@MainActor
@Test func theCaptionIslandAlsoFitsItsTrailingText() {
    let c = makeController()
    c.setUpcoming(UpcomingEvent(title: "Report", compactText: "2h 20m", caption: "Report · 20:00", url: nil))
    c.setHovered(true)
    #expect(c.isPreviewingUpcoming)
    let needed = c.metrics.notchRect.width + 2 * c.earWidth(forText: "2h 20m")
    #expect(c.parameters.width >= needed)
    #expect(c.parameters.width > NotchMetrics.captionedMinimumWidth)
    c.setUpcoming(UpcomingEvent(title: "Report", compactText: "42m", caption: "Report · 20:00", url: nil))
    #expect(c.parameters.width == NotchMetrics.captionedMinimumWidth, "a short countdown fits the default ear")
}

/// The live charging state is background (2026-10-01): alone on the
/// island it yields to the hover preview, and a blip over it still wins.
@MainActor
@Test func theChargingStateAloneYieldsToTheHoverPreview() {
    let c = makeController()
    c.setActivities([.init(id: "charging", title: "Charging", compactText: "37%", symbolName: "battery.100percent.bolt")], overflow: 0)
    #expect(c.state == .activity)
    c.setUpcoming(UpcomingEvent(title: "Standup", compactText: "42m", caption: "Standup · 10:00", url: nil))
    c.setHovered(true)
    #expect(c.state == .peek && c.isPreviewingUpcoming, "the preview, not the charger")
    c.setHovered(false)
    #expect(c.state == .activity)
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill"), .init(id: "charging", title: "Charging", compactText: "37%", symbolName: "battery.100percent.bolt")], overflow: 0)
    c.setHovered(true)
    #expect(c.state == .activity, "a real blip over it keeps the island")
}

/// A scoreline from an iPhone Live Activity (2026-10-01): a crest and a
/// figure in each ear, the island widened to fit the wider of the two,
/// the crests decoded once per change, and a hover that opens the card
/// ahead of the now-playing one.
@MainActor
@Test func aScorelinePairsTheEarsAndOpensItsCardOnHover() {
    let c = makeController()
    let crest = NSBitmapImageRep(cgImage: solidImage(width: 48, height: 48)).representation(using: .png, properties: [:])!
    let score = NotchController.ActivityDisplay.Score(
        home: .init(name: "Indonesia", value: "6", crest: crest),
        away: .init(name: "Bangladesh", value: "1", crest: crest),
        status: "HT", clock: "5:56", title: "Cup")
    c.setActivities([.init(id: "live-activity", title: "Live Activity", symbolName: "iphone",
                           url: URL(string: "ledge://live-activity"), score: score)], overflow: 0)
    #expect(c.state == .activity && c.hasCard)
    #expect(c.parameters.height == c.metrics.notchRect.height, "the pairs live in the ears; the island keeps its height")
    #expect(c.leadingEarWidth > NotchMetrics.activityEarWidth, "a crest and a figure need more than a glyph")
    #expect(c.homeCrestImage != nil && c.awayCrestImage != nil)
    #expect(c.linkURL == URL(string: "ledge://live-activity"))

    let before = c.homeCrestImage
    c.setActivities([.init(id: "live-activity", title: "Live Activity", score: score)], overflow: 0)
    #expect(c.homeCrestImage === before, "the same crest is not decoded again")

    c.setMedia(MediaPresentation(title: "Song", artist: nil, artwork: nil, isPlaying: true, elapsed: 0, duration: 100))
    c.setHovered(true)
    #expect(c.state == .expanded && c.panel == .liveActivity, "the card first, music a swipe away")
    #expect(c.availablePanels == [.liveActivity, .media])
    #expect(c.swipe(.next) && c.panel == .media)
    c.setHovered(false)
    #expect(c.panel == .media && c.state == .activity)
    c.setActivities([.init(id: "charging", title: "Charging", compactText: "37%")], overflow: 0)
    #expect(!c.hasCard && c.homeCrestImage == nil)
}

/// An activity that is not a match keeps the glyph and opens its lines.
@MainActor
@Test func aLiveActivityWithoutSidesOpensItsLines() {
    let c = makeController()
    c.setActivities([.init(id: "live-activity", title: "PGA Tour", compactText: "Round 1, In Progress",
                           symbolName: "iphone", lines: ["PGA Tour", "Round 1, In Progress"])], overflow: 0)
    #expect(c.hasCard && c.score == nil)
    c.setHovered(true)
    #expect(c.state == .expanded && c.panel == .liveActivity)
}

private func solidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.1, green: 0.15, blue: 0.18, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// A virtual notch (2026-10-21): hidden and tucked draw nothing, so no
/// black tab is left at the top of a screen without a notch; a live
/// island is the real notch's size.
@MainActor
@Test func aVirtualNotchDrawsNothingWhenHiddenOrTucked() {
    let c = NotchController(
        metrics: NotchMetrics(notchRect: CGRect(x: 870.5, y: 0, width: 179, height: 32), isVirtual: true),
        reduceMotion: false
    )
    #expect(c.state == .hidden)
    #expect(c.parameters.height == 0)
    c.setActivityCount(1)
    #expect(c.parameters == c.metrics.oneActivity)
    c.setTucked(true)
    #expect(c.parameters.height == 0)
}

// MARK: - The pill's card strip (2026-10-21)

@MainActor
private func makePillController() -> NotchController {
    NotchController(metrics: NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true))
}

@MainActor
private func openNowPlayingCard(_ c: NotchController) {
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
    c.click()
}

/// Now-playing alone: its artwork moves into the card, the ears are
/// empty, and the pill's card has no strip.
@MainActor
@Test func theEarsAreEmptyAboveACardOfNowPlayingAlone() {
    let c = makePillController()
    openNowPlayingCard(c)
    #expect(c.state == .expanded)
    #expect(!c.earsShowAboveCard)
    #expect(c.parameters.height == 148)
}

/// A blip leading while the card is open shows in the ears, and the
/// pill's card grows its strip back for it.
@MainActor
@Test func aBlipOverAnOpenCardGrowsThePillsStrip() {
    let c = makePillController()
    openNowPlayingCard(c)
    c.setActivities([
        .init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill"),
        .init(id: "media", title: "Song", detail: "Artist"),
    ], overflow: 0)
    #expect(c.state == .expanded)
    #expect(c.earsShowAboveCard)
    #expect(c.parameters.height == 168)
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.parameters.height == 148, "and shrinks again when the blip ends")
}

/// The "+N" pip sits in the trailing ear, so it counts too.
@MainActor
@Test func theOverflowPipCountsAsSomethingAboveTheCard() {
    let c = makePillController()
    openNowPlayingCard(c)
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 2)
    #expect(c.earsShowAboveCard)
}

@MainActor
private func matchScore() -> NotchController.ActivityDisplay.Score {
    NotchController.ActivityDisplay.Score(
        home: .init(name: "Indonesia", value: "6", crest: nil),
        away: .init(name: "Bangladesh", value: "1", crest: nil),
        status: "HT", clock: "5:56", title: "Cup")
}

/// A match's own card open: both ears are empty (the crests fly into the
/// card), so the pill's card has no strip.
@MainActor
@Test func anOpenMatchCardHasNoStrip() {
    let c = makePillController()
    c.setActivities([.init(id: "live-activity", title: "Live Activity", symbolName: "iphone", score: matchScore())], overflow: 0)
    c.setHovered(true)
    #expect(c.state == .expanded && c.panel == .liveActivity)
    #expect(!c.earsShowAboveCard)
    #expect(c.parameters.height == 148)
}

/// A match leading over the pinned music card: the crests stay in the
/// ears, so the strip is back.
@MainActor
@Test func aMatchOverTheMusicCardGrowsTheStrip() {
    let c = makePillController()
    openNowPlayingCard(c)
    c.setActivities([
        .init(id: "live-activity", title: "Live Activity", symbolName: "iphone", score: matchScore()),
        .init(id: "media", title: "Song", detail: "Artist"),
    ], overflow: 0)
    #expect(c.state == .expanded && c.panel == .media)
    #expect(c.earsShowAboveCard)
    #expect(c.parameters.height == 168)
}

/// Only an open card has ears above it.
@MainActor
@Test func earsAboveTheCardNeedAnOpenCard() {
    let c = makePillController()
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")], overflow: 0)
    #expect(c.state == .activity)
    #expect(!c.earsShowAboveCard)
}

/// Lid shut with a blip up: the metrics swap to the pill and the very
/// next read is the pill's size, nothing of the notch left over.
@MainActor
@Test func swappingToAPillMidBlipResizesAtOnce() {
    let c = makeController()
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")], overflow: 0)
    #expect(c.parameters.width == 255)
    c.metrics = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    #expect(c.parameters == c.metrics.oneActivity)
    #expect(c.parameters.width == 120)
    #expect(c.parameters.topRadius == 16)
}

import Testing
import Foundation
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
    #expect(c.parameters == c.metrics.captioned)

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
@Test func lockingShowsTheNowPlayingPanelAndUnlockingRestoresTheCompactIsland() {
    let c = makeController()
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.state == .activity)

    c.setLocked(true)
    #expect(c.isLocked)
    #expect(c.state == .expanded, "on the lock screen the now-playing card is the whole point")
    #expect(!c.isPinnedOpen, "a lock is not a pin: unlocking must close it")

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
    #expect(c.parameters == c.metrics.captioned, "ears plus the caption line, like the reminder blip")
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
    #expect(c.parameters == c.metrics.captioned)
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
    let item = UpcomingEvent(title: "Standup", compactText: "42m", caption: "Standup · 10:00", when: "10:00–10:15", url: nil)
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.setHovered(true)
    #expect(c.state == .expanded && c.panel == .media)
    #expect(!c.swipe(.next), "one mode only: not taken, so the presenter skips the track")

    c.setAgenda([item])
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
    d.setAgenda([item])
    d.setHovered(true)
    #expect(d.state == .peek && d.isPreviewingUpcoming)
    #expect(d.swipe(.next) && d.state == .expanded && d.panel == .calendar)
    #expect(d.parameters == d.metrics.expanded)
    d.setHovered(false)
    #expect(d.state == .hidden && d.panel == .media)
    d.setAgenda([])
    #expect(d.availablePanels.isEmpty)
}

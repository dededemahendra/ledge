import AppKit
import Foundation
import Observation

public enum NotchState: Sendable, Equatable {
    case hidden
    case peek
    case activity
    case expanded
}

/// Now-playing state for the island's media surface. A pure value type — no
/// dependency on `MediaService`/`MediaPayload`, so `NotchKit` stays
/// independent of how the state was sourced (same reasoning as
/// `NotchController.ActivityDisplay` decoupling this module from
/// `ActivityKit`). `AppModel` converts `MediaPayload` into this.
public struct MediaPresentation: Sendable, Equatable {
    public let title: String
    public let artist: String?
    public let artwork: Data?
    public let isPlaying: Bool
    /// The position as of `anchor`; the live position is arithmetic from
    /// there (`position(at:)`), so the card can draw it exactly on every
    /// frame instead of chasing a once-a-second tick (2026-09-30).
    public let elapsed: Double
    public let duration: Double?
    public let anchor: Date
    /// Seconds of playback per second of wall clock: 0 paused, 1 playing,
    /// the player's own rate otherwise.
    public let rate: Double
    /// `nil`: the source does not report shuffle (browsers), and the
    /// panel's shuffle button is disabled. Otherwise the button shows it.
    public let isShuffling: Bool?
    /// Decoded alongside shuffle for the day a repeat control has a slot
    /// again (the output picker took repeat's on 2026-09-28); not drawn.
    public let repeatMode: RepeatMode?

    public enum RepeatMode: Sendable, Equatable {
        case off, one, all
    }

    /// The card's favourite star. `.unsupported` disables it (every source
    /// but Apple Music); `.unknown` is enabled but hollow, before the first
    /// tap opts into asking Music; then `.on`/`.off` follow the track.
    public enum Favorite: Sendable, Equatable {
        case unsupported, unknown, on, off
    }
    public let favorite: Favorite

    public init(
        title: String, artist: String?, artwork: Data?,
        isPlaying: Bool, elapsed: Double, duration: Double?,
        anchor: Date = Date(), rate: Double? = nil,
        isShuffling: Bool? = nil, repeatMode: RepeatMode? = nil,
        favorite: Favorite = .unsupported
    ) {
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
        self.anchor = anchor
        self.rate = rate ?? (isPlaying ? 1 : 0)
        self.isShuffling = isShuffling
        self.repeatMode = repeatMode
        self.favorite = favorite
    }

    /// `0...1`, or exactly `0` when duration is unknown or zero — a live
    /// stream (no duration) must never render a meaningless full bar.
    public var progress: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    /// The position `now`, extrapolated from the anchor and clamped to the
    /// track; never behind the anchor.
    public func position(at now: Date) -> Double {
        let advanced = elapsed + max(0, now.timeIntervalSince(anchor)) * rate
        guard let duration, duration > 0 else { return max(0, advanced) }
        return min(duration, max(0, advanced))
    }

    public func progress(at now: Date) -> Double {
        guard let duration, duration > 0 else { return 0 }
        return min(1, max(0, position(at: now) / duration))
    }

    public func elapsedText(at now: Date) -> String { Self.clock(position(at: now)) }

    public func remainingText(at now: Date) -> String? {
        guard let duration, duration > 0 else { return nil }
        return "-" + Self.clock(max(0, duration - position(at: now)))
    }

    public var elapsedText: String { Self.clock(max(0, elapsed)) }

    /// `nil` when duration is unknown — there is nothing to count down to.
    public var remainingText: String? {
        guard let duration, duration > 0 else { return nil }
        return "-" + Self.clock(max(0, duration - min(elapsed, duration)))
    }

    /// "m:ss" under an hour, "h:mm:ss" from an hour up — "61:01" for a
    /// 1h01m position is not a clock anyone reads (2026-09-29; podcasts and
    /// videos routinely run past an hour).
    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Playback controls the panel can emit. `AppModel` turns these into
/// `MediaCommand`s — `NotchKit` stays independent of `MediaService` here too.
///
/// `seek` carries a **fraction**, not seconds: the view (the scrub bar) knows
/// its own width, not the track's duration; only `AppModel`, which holds the
/// live `MediaPayload`, knows that.
public enum NotchIntent: Sendable, Equatable {
    case togglePlayPause
    case next
    case previous
    // Stateless toggles: the adapter accepts them but `MediaPayload` does not
    // yet decode shuffleMode/repeatMode, so the buttons fire without showing
    // an active state. Decode-and-highlight is a later, separate step.
    case toggleShuffle
    case toggleRepeat
    case seek(fraction: Double)
    /// Make this output (an `OutputOption.id`, CoreAudio's device UID) the
    /// default. `AppModel` hands it to `DeviceService`.
    case selectOutput(id: String)
    /// A click on a blip that carries a link (`ActivityDisplay.url` — a
    /// meeting reminder's join URL). `AppModel` opens it.
    case open(URL)
    /// Bring the app that is playing to the front (a click on the card's
    /// artwork or title — the Dynamic Island's own gesture for "take me
    /// there"). `AppModel` resolves which app from the live payload.
    case openSource
    /// The card's star: favourite or un-favourite the current track.
    case toggleFavorite
}

/// One entry of the panel's output picker. A pure value like
/// `MediaPresentation`: `NotchKit` does not know CoreAudio.
public struct OutputOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let symbolName: String
    public let isCurrent: Bool

    public init(id: String, name: String, symbolName: String, isCurrent: Bool) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.isCurrent = isCurrent
    }
}

/// Single source of truth for what the island is doing.
///
/// Deliberately free of timers, AppKit and IO so every transition is testable.
/// Whoever owns this calls the mutators; TTL expiry lives in `ActivityQueue`.
@MainActor
@Observable
public final class NotchController {
    /// UI-facing projection of an activity. Keeps `NotchKit` independent of
    /// `ActivityKit`'s storage types.
    public struct ActivityDisplay: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String?
        /// Very short glanceable form for the trailing ear — "87%", "50%".
        ///
        /// Required, not decorative: at one activity the island stays exactly
        /// notch-height, so `detailRow` is gated off and `title` has nowhere to
        /// render. Without this the common single-activity case shows a glyph and
        /// no words at all. The ear is only ~38pt wide, so this must stay to a
        /// few characters — the full `title` will not fit.
        public let compactText: String?
        /// SF Symbol shown in the leading ear, e.g. "speaker.wave.2.fill".
        /// `nil` falls back to the plain activity dot.
        public let symbolName: String?
        /// `0...1` progress bar shown in the detail row, or `nil` for
        /// activities without one (e.g. a plain status line).
        public let barFill: Double?
        /// Encoded image for the leading ear — a device activity's product
        /// render (AirPods, from the system's own assets). Wins over
        /// `symbolName`, which stays as the fallback when decoding fails.
        public let artwork: Data?
        /// Colour for the glyph when the state means something the system
        /// colours too: `.positive` (green, charging/charged) or `.warning`
        /// (red, low battery). `nil` is the island's white.
        public enum Tint: Sendable, Equatable {
            case positive, warning
            /// An Apple system colour by name — see `SystemTint`.
            case system(String)
        }
        public let tint: Tint?
        /// What a click on the blip opens while it shows — see
        /// `NotchController.tap()`. `nil`: the blip is just a blip.
        public let url: URL?
        /// Several readings side by side in the trailing ear — a bud's and
        /// a case's charge (2026-09-30) — drawn instead of `compactText`;
        /// the island widens to fit them.
        public struct Part: Sendable, Equatable {
            public let symbolName: String?
            public let text: String

            public init(symbolName: String?, text: String) {
                self.symbolName = symbolName
                self.text = text
            }
        }
        public let parts: [Part]?

        public init(
            id: String,
            title: String,
            detail: String? = nil,
            compactText: String? = nil,
            symbolName: String? = nil,
            barFill: Double? = nil,
            artwork: Data? = nil,
            tint: Tint? = nil,
            url: URL? = nil,
            parts: [Part]? = nil
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.compactText = compactText
            self.symbolName = symbolName
            self.barFill = barFill.map { min(1, max(0, $0)) }
            self.artwork = artwork
            self.tint = tint
            self.url = url
            self.parts = parts
        }
    }

    public private(set) var state: NotchState = .hidden
    public private(set) var isHovered = false
    public private(set) var activityCount = 0
    public private(set) var activities: [ActivityDisplay] = []
    public private(set) var overflowCount = 0

    /// Live now-playing state, or `nil` when nothing is playing.
    /// `AppModel` keeps this in step with `MediaService`'s stream and also
    /// inserts a matching sticky (`ttl: nil`) activity into its queue — the
    /// two are set together but are deliberately separate fields: `activities`
    /// carries only what every activity kind has in common, while `media`
    /// carries the richer artwork/position/duration the panel needs and no
    /// other kind has.
    public private(set) var media: MediaPresentation?

    /// The panel's output picker, kept current by `AppModel` from
    /// `DeviceService`. Empty until the device service reports.
    public private(set) var outputs: [OutputOption] = []

    /// `AppModel` inserts the sticky media record with this id.
    public static let mediaActivityID = "media"

    public var isMediaLeading: Bool {
        activities.first?.id == Self.mediaActivityID
    }

    /// One line under the hole for a few seconds after a song changes —
    /// "Title · Artist" (2026-09-29, from the reference app). `AppModel`
    /// sets it on every title change and clears it after
    /// `captionDuration`; the presenter resyncs the window because the
    /// island grows to `NotchMetrics.captioned` while it shows. Only
    /// drawn while media LEADS at activity size: a blip pre-empting the
    /// island takes it whole, and at `.expanded` the panel already says it.
    public private(set) var caption: String?
    public static let captionDuration: TimeInterval = 3

    public func setCaption(_ caption: String?) {
        self.caption = caption
    }

    /// A song caption belongs to media leading; a meeting blip
    /// (2026-09-29) carries its own — "Title · 10:00". Any other blip
    /// pre-empting the island takes it whole.
    public var hasCaption: Bool {
        state == .activity && caption != nil && (isMediaLeading || isCalendarLeading)
    }

    /// `AppModel` inserts the Focus blip with this id.
    public static let focusActivityID = "focus"

    /// `AppModel` inserts the meeting reminder with this id.
    public static let calendarActivityID = "calendar"

    /// `AppModel` inserts the running timer/stopwatch with this id. The
    /// view draws its countdown as a ring (`barFill`) and keeps its digits
    /// from bumping every second.
    public static let timerActivityID = "timer"

    public var isCalendarLeading: Bool {
        activities.first?.id == Self.calendarActivityID
    }

    /// The next calendar event, shown on hover when there is nothing else
    /// to show — see `UpcomingEvent` and `isPreviewingUpcoming`.
    public private(set) var upcoming: UpcomingEvent?

    public func setUpcoming(_ upcoming: UpcomingEvent?) {
        guard upcoming != self.upcoming else { return }   // set every tick; only a change should re-render
        self.upcoming = upcoming
    }

    /// Hovered, nothing playing, no blip live, and an event coming up: the
    /// peek becomes the meeting blip's layout with that event in it.
    public var isPreviewingUpcoming: Bool {
        state == .peek && upcoming != nil
    }

    // MARK: - Modes of the open card (2026-09-30)

    /// What the open card shows: the now-playing card, or the calendar's
    /// "Up next" list. A two-finger swipe moves between the ones available.
    public enum Panel: Sendable, Equatable {
        case media, calendar
    }

    public private(set) var panel: Panel = .media
    /// The way the last mode change went, so the view slides the panels
    /// that way: `.next` brings the new mode in from the right.
    public private(set) var lastSwipe: SwipeToSkipTracker.Direction = .next

    /// What the calendar mode draws; `nil` means no calendar mode (no
    /// calendar access).
    public private(set) var calendarMode: CalendarModeData?

    public func setCalendarMode(_ data: CalendarModeData?) {
        guard data != calendarMode else { return }
        calendarMode = data
        if calendarMode == nil, panel == .calendar { panel = .media }
        recomputeState()
    }

    /// The modes there are right now, in swipe order.
    public var availablePanels: [Panel] {
        var panels: [Panel] = []
        if media != nil { panels.append(.media) }
        if calendarMode != nil { panels.append(.calendar) }
        return panels
    }

    /// A two-finger swipe. On the open card, the next or previous mode; on
    /// the next-item preview, the calendar mode. Returns whether the
    /// swipe was taken — otherwise the presenter treats it as a track skip.
    /// At the last mode a swipe is taken and nothing moves: a swipe on the
    /// card never skips a track by accident.
    public func swipe(_ direction: SwipeToSkipTracker.Direction) -> Bool {
        let panels = availablePanels
        if state == .expanded, panels.count > 1, let index = panels.firstIndex(of: panel) {
            let target = direction == .next ? index + 1 : index - 1
            if panels.indices.contains(target) {
                lastSwipe = direction
                panel = panels[target]
                recomputeState()
            }
            return true
        }
        if isPreviewingUpcoming, calendarMode != nil {
            lastSwipe = direction
            panel = .calendar
            recomputeState()
            return true
        }
        return false
    }

    /// What the caption line under the hole says right now, if anything:
    /// the song/meeting caption at activity size, or the previewed event.
    public var captionText: String? {
        if isPreviewingUpcoming { return upcoming?.caption }
        return hasCaption ? caption : nil
    }

    /// Feedback for a swipe-to-skip: the skip glyph takes the leading ear
    /// for a beat (`skipHintDuration`), then the artwork comes back.
    public enum SkipHint: Sendable, Equatable {
        case next, previous
    }

    public private(set) var skipHint: SkipHint?
    public static let skipHintDuration: TimeInterval = 0.7

    public func setSkipHint(_ hint: SkipHint?) {
        skipHint = hint
    }

    public func setOutputs(_ outputs: [OutputOption]) {
        self.outputs = outputs
        if outputs.count < 2 { isOutputPickerOpen = false }   // nothing to choose from
    }

    /// The output picker's list is open below the controls. Lives here,
    /// not in the view, because it changes the island's SIZE
    /// (`NotchMetrics.expanded(outputRows:)`). Closes itself whenever the
    /// panel closes (`recomputeState`), after a pick, and when there is
    /// nothing to pick from.
    public private(set) var isOutputPickerOpen = false

    public func setOutputPicker(open: Bool) {
        isOutputPickerOpen = open && state == .expanded && outputs.count >= 2
    }

    /// Set by whoever owns this controller (`AppModel`) to receive playback
    /// commands the panel emits. `nil` is a safe no-op default, same reasoning
    /// as `NotchRootView.onTap`.
    public var onIntent: ((NotchIntent) -> Void)?

    public var metrics: NotchMetrics
    /// `var`, not `let`: this is an always-running background agent, and a
    /// user who flips Reduce Motion while it is running must not have to
    /// quit and relaunch to get the crossfade. `NotchPresenter` keeps this
    /// in step with `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
    public var reduceMotion: Bool

    public init(metrics: NotchMetrics, reduceMotion: Bool = false) {
        self.metrics = metrics
        self.reduceMotion = reduceMotion
    }

    public var isVisible: Bool { state != .hidden }

    /// The island a caption line needs: the line at the caption row's own
    /// fonts (11 pt semibold title, regular rest), plus its 14 pt side
    /// paddings and room to spare (2026-10-01).
    func captionWidth(_ caption: String?) -> CGFloat {
        guard let caption else { return NotchMetrics.captionedMinimumWidth }
        let parts = caption.components(separatedBy: " · ")
        let title = NSAttributedString(string: parts.first ?? caption, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).size().width
        let rest = parts.count > 1
            ? NSAttributedString(string: " · " + parts.dropFirst().joined(separator: " · "), attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular)]).size().width
            : 0
        return ceil(title + rest) + 2 * 14 + 16
    }

    /// The ear the leading activity's trailing text needs (2026-09-30: a
    /// Focus's name stands where "On" was): measured at the 11 pt medium
    /// `compactValue` draws it, plus breathing room. Four characters or
    /// fewer — every percentage, "Now", "Off" — leave the default.
    public var leadingEarWidth: CGFloat {
        if let parts = activities.first?.parts, !parts.isEmpty {
            // Readings: 10 pt medium, a glyph's ~14 pt where one is set,
            // 2 pt inside a reading and 7 pt between them, as `readings`
            // in the view lays them out.
            let font = NSFont.systemFont(ofSize: 10, weight: .medium)
            let widths = parts.map { part -> CGFloat in
                (part.symbolName == nil ? 0 : 16) + ceil(NSAttributedString(string: part.text, attributes: [.font: font]).size().width)
            }
            return widths.reduce(0, +) + CGFloat(max(0, parts.count - 1)) * 7 + 16
        }
        guard let text = activities.first?.compactText, text.count > 4 else { return NotchMetrics.activityEarWidth }
        let width = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).size().width
        return ceil(width) + 16
    }

    /// `AppModel` inserts every volume/brightness record with this id
    /// (`ActivityKind.hud.rawValue` — a string, not the enum, since `NotchKit`
    /// has no dependency on `ActivityKit`; the same cross-module convention
    /// `NotchRootView.mediaActivityID` already relies on).
    public static let hudActivityID = "hud"

    /// True while a volume/brightness HUD is the leading activity: it owns
    /// the one-activity island — glyph left, percentage right — whatever
    /// else is queued behind it. A HUD is a 1.5s blip that answers exactly
    /// one question (what, and how much); while it is live the island says
    /// only that. It used to share the two-slot size with a sticky media
    /// activity — which, with music playing, is EVERY volume press. A wider
    /// labelled island ("Sound" + bar, matching the reference app) was
    /// tried in between and dropped at the user's request for glyph +
    /// percentage, the same shape as the power blip.
    public var isHUDLeading: Bool {
        activities.first?.id == Self.hudActivityID
    }

    /// `AppModel` inserts every device (output-route) record with this id.
    public static let deviceActivityID = "device"

    /// `AppModel` inserts every power record with this id.
    public static let powerActivityID = "power"

    /// A charging/battery blip leads: the plain one-activity island, glyph
    /// left (bolt, plug, battery fill), percentage right, no words — the
    /// user's call (2026-09-28) after a labelled "Charging …… 95%" row was
    /// tried. Whatever is queued behind it waits; it used to fall into the
    /// two-slot layout over music with a grey dot for a glyph.
    public var isPowerLeading: Bool {
        activities.first?.id == Self.powerActivityID
    }

    /// A device blip leads. It never grows the island (user's call,
    /// 2026-09-28, after "External Headphones" landed in the two-slot
    /// layout over music): the island stays at one-activity size, and with
    /// music playing the artwork keeps the leading ear while the device's
    /// icon takes the trailing one for the blip's 3s — "what just
    /// connected" reads as a swap in the ear, not a slab with a caption.
    public var isDeviceLeading: Bool {
        activities.first?.id == Self.deviceActivityID
    }

    public var parameters: NotchShapeParameters {
        switch state {
        case .hidden:
            return metrics.collapsed
        case .peek:
            return upcoming != nil ? metrics.captioned(fitting: captionWidth(upcoming?.caption)) : metrics.peek
        case .activity:
            // One size for every activity, however many are queued
            // (2026-09-29): the "grow down when crowded" two-slot layout
            // was retired once HUD, power and device blips each learned to
            // own the island alone. The one thing that still grows the
            // compact island is a song-change caption, and only while
            // media itself leads.
            return hasCaption ? metrics.captioned(fitting: captionWidth(caption)) : metrics.oneActivity(earWidth: leadingEarWidth)
        case .expanded:
            return metrics.expanded(outputRows: panel == .media && isOutputPickerOpen ? outputs.count : 0)
        }
    }

    public func setHovered(_ hovered: Bool) {
        isHovered = hovered
        // Leaving puts the card back on now-playing for next time, unless
        // it is pinned where it is.
        if !hovered, !isPinnedOpen { panel = .media }
        recomputeState()
    }

    /// The screen is locked (`loginwindow` owns it). Spec §7: lock-screen
    /// mode is display-only — with media playing the panel shows the
    /// now-playing card without its controls (`NotchRootView` reads this
    /// flag to strip them), since a panel above the lock shield can render
    /// but cannot reliably take clicks. Charging/HUD/device activities keep
    /// appearing in the ears exactly as when unlocked.
    public private(set) var isLocked = false

    public func setLocked(_ locked: Bool) {
        isLocked = locked
        recomputeState()
    }

    /// Pins the now-playing card open. A no-op without a card (2026-09-29:
    /// the expanded panel is only ever the card — a click on a lone blip
    /// used to pin open the pre-card title-and-bar layout around it) and
    /// without an island to expand (zero-width notch rect — no notch on
    /// this Mac, or a display-hot-plug gap; without that guard a pin
    /// latched `.expanded` with no window ever created to show it, and
    /// `recomputeState()`'s first line returned early on `.expanded`
    /// forever after — hover permanently inert).
    public func click() {
        guard metrics.notchRect.width > 0, media != nil else { return }
        isPinnedOpen = true
        state = .expanded
    }

    /// A click on the island (as opposed to the menu bar's "Toggle Panel",
    /// which is `click()`/`dismiss()` unconditionally):
    /// - on a hover-opened panel: nothing. The cursor already holds it
    ///   open; a click on its body is not a request, and turning it into a
    ///   pin made the panel outlive the hover for no reason the user could
    ///   see (the 2026-09-28 "click the notch, then…" report started here).
    ///   The panel's own buttons still get their taps first.
    /// - on a pinned panel: unpin. If the cursor is still there it stays
    ///   hover-open, so nothing visibly changes — but leaving now closes it.
    /// - otherwise: pin the card open, but only when there is a card; a
    ///   click on an empty peek or on a lone blip must not open an empty
    ///   slab (2026-09-29: nor the old title-and-bar list around the blip).
    public func tap() {
        if state == .expanded {
            if isPinnedOpen { dismiss() }
            return
        }
        // The previewed event (hover, nothing playing) and a blip that
        // carries a link — a meeting reminder's join URL — are buttons for
        // as long as they show (2026-09-29): the click opens the link, and
        // wins over pinning the card behind it.
        if let url = linkURL {
            emit(.open(url))
            return
        }
        guard media != nil else { return }
        click()
    }

    /// The link a tap would open right now: the previewed event's, or the
    /// leading blip's while it shows; `nil` at `.expanded` (the panel's
    /// own buttons take clicks there). The view reads this to dip the
    /// content on press and show the link pointer — the island only
    /// looks like a button when it is one.
    public var linkURL: URL? {
        guard state != .expanded else { return nil }
        if isPreviewingUpcoming { return upcoming?.url }
        return activities.first?.url
    }

    /// Unpins. If the cursor is still over the island and there is media
    /// to show, `recomputeState()` lands straight back on `.expanded` —
    /// hover-opened, no longer pinned — because under the hover model the
    /// cursor being there IS the request to see the panel. Escape/click-
    /// outside/Toggle Panel therefore only visibly close a panel the
    /// cursor has already left, or one with nothing to hover open.
    public func dismiss() {
        guard state == .expanded else { return }
        isPinnedOpen = false
        panel = .media
        state = .hidden          // recomputeState restores peek/activity if warranted
        recomputeState()
    }

    /// True while the panel was opened by `click()` (a tap on the island,
    /// or the menu bar's "Toggle Panel") and not yet `dismiss()`ed. A
    /// pinned panel stays open whatever the cursor does; a hover-opened one
    /// is derived from `isHovered` every time and closes when the cursor
    /// leaves. Two distinct things, kept distinct: without this flag,
    /// `recomputeState()` could not tell "expanded because hovered" from
    /// "expanded because asked", and would either close a pinned panel on
    /// unhover or never close a hovered one.
    public private(set) var isPinnedOpen = false

    public func setActivityCount(_ count: Int) {
        activityCount = max(0, count)
        recomputeState()
    }

    public func setActivities(_ activities: [ActivityDisplay], overflow: Int) {
        let shapeBefore = parameters
        let blipBefore = leadingBlipKey
        self.activities = activities
        self.overflowCount = max(0, overflow)
        setActivityCount(activities.count + max(0, overflow))
        // A blip landing on an island that does not change shape — the
        // charger going in while music shows, say — gets no growth spring
        // to announce it. Count it, and the view pulses the whole island.
        if let key = leadingBlipKey, key != blipBefore, parameters == shapeBefore {
            blipPulse += 1
        }
    }

    /// Bumped each time a blip (HUD, power, device) arrives WITHOUT the
    /// island changing shape (2026-09-29, user's report: "not working on
    /// plug" — with music playing the island was already there at the same
    /// size, so nothing moved). `NotchRootView` scales the island up ~5%
    /// from its top edge and springs back on every change of this.
    public private(set) var blipPulse = 0

    /// Identity of the leading blip, if the leading activity is one.
    /// Title included so plug → unplug (same id, new title) pulses again.
    private var leadingBlipKey: String? {
        guard let first = activities.first,
              [Self.hudActivityID, Self.powerActivityID, Self.deviceActivityID].contains(first.id)
        else { return nil }
        return "\(first.id)|\(first.title)"
    }

    /// Does NOT touch `state`/`activityCount` itself — `AppModel` drives
    /// those the usual way, via `setActivities`, by inserting a sticky
    /// activity of kind `.media` into the same `ActivityQueue` every other
    /// kind goes through. This just carries the richer presentation data
    /// (artwork, elapsed/duration) that activity's plain title/detail can't.
    /// `media.artwork` decoded exactly once per change. The views used to
    /// call `NSImage(data:)` in their bodies, i.e. once a second while
    /// playing (every position tick rebuilds `media`) and again on every
    /// scrub update (review, 2026-09-29).
    public private(set) var mediaArtworkImage: NSImage?

    public func setMedia(_ media: MediaPresentation?) {
        if media?.artwork != self.media?.artwork {
            mediaArtworkImage = media?.artwork.flatMap(NSImage.init(data:))
        }
        // A pin is a pin on the now-playing card (2026-09-29): when the
        // player quits or crashes and takes the card with it, the pin goes
        // too, so the island falls back to a blip, a peek or idle instead
        // of holding a 390x168 slab with nothing in it. Only the card's
        // DEPARTURE releases it — nil-to-nil is stream noise (a disallowed
        // source's diff, say) and must not unpin a blip's own detail panel.
        let cardWentAway = self.media != nil && media == nil
        self.media = media
        if cardWentAway { isPinnedOpen = false }
        // Media is what hover opens (see `recomputeState`), so media
        // arriving under a cursor already parked on the island must open
        // the panel, and media going away must close a hover-opened one.
        recomputeState()
    }


    /// Forwards a panel-originated command out to `onIntent`. Public so the
    /// view layer (`MediaPanelView`, `NotchRootView`'s ears) can call it
    /// without knowing who — if anyone — is listening.
    public func emit(_ intent: NotchIntent) {
        onIntent?(intent)
    }

    /// A pinned panel outranks everything. Otherwise hover opens the panel
    /// whenever there is media to put in it — the now-playing card is the
    /// one expanded surface with controls, so it is the one worth opening
    /// for; a lone HUD or battery blip already says everything in its ears,
    /// and hovering it must not balloon it into a 168pt slab. Below that,
    /// activities outrank hover, and hover with nothing to show is the
    /// small peek.
    ///
    /// Hover-driven expansion is DERIVED here on every call, never latched:
    /// that is what makes the cursor leaving close it (`setHovered(false)`
    /// lands here) and media stopping close it (`setMedia(nil)` lands here).
    /// No flicker risk at the boundary: every hover transition only ever
    /// grows the island (peek/activity -> expanded), so a cursor that was
    /// inside the small shape is still inside the big one.
    private func recomputeState() {
        if isPinnedOpen {
            state = .expanded
        } else if isHovered, media != nil {
            state = .expanded
        } else if isHovered, panel == .calendar, calendarMode != nil {
            // The calendar mode, swiped open from the preview.
            state = .expanded
        } else if activityCount > 0 {
            state = .activity
        } else if isHovered {
            state = .peek
        } else {
            state = .hidden
        }
        if state != .expanded || panel != .media { isOutputPickerOpen = false }
    }
}

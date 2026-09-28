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
    public let elapsed: Double
    public let duration: Double?

    public init(
        title: String, artist: String?, artwork: Data?,
        isPlaying: Bool, elapsed: Double, duration: Double?
    ) {
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
    }

    /// `0...1`, or exactly `0` when duration is unknown or zero — a live
    /// stream (no duration) must never render a meaningless full bar.
    public var progress: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    public var elapsedText: String { Self.clock(max(0, elapsed)) }

    /// `nil` when duration is unknown — there is nothing to count down to.
    public var remainingText: String? {
        guard let duration, duration > 0 else { return nil }
        return "-" + Self.clock(max(0, duration - min(elapsed, duration)))
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
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

        public init(
            id: String,
            title: String,
            detail: String? = nil,
            compactText: String? = nil,
            symbolName: String? = nil,
            barFill: Double? = nil,
            artwork: Data? = nil
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.compactText = compactText
            self.symbolName = symbolName
            self.barFill = barFill.map { min(1, max(0, $0)) }
            self.artwork = artwork
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

    /// `AppModel` inserts every volume/brightness record with this id
    /// (`ActivityKind.hud.rawValue` — a string, not the enum, since `NotchKit`
    /// has no dependency on `ActivityKit`; the same cross-module convention
    /// `NotchRootView.mediaActivityID` already relies on).
    public static let hudActivityID = "hud"

    /// True while a volume/brightness HUD is the leading activity — the case
    /// that gets the `NotchMetrics.hud` island and the glyph + label ear
    /// layout, whatever else is queued behind it. A HUD is a 1.5s blip that
    /// answers exactly one question (what, and how much); while it is live
    /// the island says only that. It used to share the two-slot size with a
    /// sticky media activity — which, with music playing, is EVERY volume
    /// press — and that layout stranded the glyph top-left, put the level
    /// in the ear AND the detail row, and grew the island for a word.
    /// Whatever it pre-empted (the artwork, the battery) comes straight
    /// back when it expires.
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
            return metrics.peek
        case .activity:
            if isHUDLeading { return metrics.hud }
            if isDeviceLeading || isPowerLeading { return metrics.oneActivity }
            return activityCount >= 2 ? metrics.twoActivities : metrics.oneActivity
        case .expanded:
            return metrics.expanded
        }
    }

    public func setHovered(_ hovered: Bool) {
        isHovered = hovered
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

    /// A no-op with no island to expand (zero-width notch rect — no notch on
    /// this Mac, or a display-hot-plug gap). Without this guard, "Toggle
    /// Panel" latches `.expanded` with no window ever created to show it,
    /// and `recomputeState()`'s very first line returns early on
    /// `.expanded` forever after — hover becomes permanently inert until
    /// Toggle Panel is pressed again.
    public func click() {
        guard metrics.notchRect.width > 0 else { return }
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
    /// - otherwise: pin open, but only when there is something to show; a
    ///   click on an empty peek must not open an empty slab.
    public func tap() {
        if state == .expanded {
            if isPinnedOpen { dismiss() }
            return
        }
        guard media != nil || activityCount > 0 else { return }
        click()
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
        self.activities = activities
        self.overflowCount = max(0, overflow)
        setActivityCount(activities.count + max(0, overflow))
    }

    /// Does NOT touch `state`/`activityCount` itself — `AppModel` drives
    /// those the usual way, via `setActivities`, by inserting a sticky
    /// activity of kind `.media` into the same `ActivityQueue` every other
    /// kind goes through. This just carries the richer presentation data
    /// (artwork, elapsed/duration) that activity's plain title/detail can't.
    public func setMedia(_ media: MediaPresentation?) {
        self.media = media
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
        } else if isLocked, media != nil {
            // Lock screen: now-playing stays up, display-only (see
            // `setLocked`). Above `isHovered` only for clarity — with the
            // cursor also there the outcome is the same.
            state = .expanded
        } else if isHovered, media != nil {
            state = .expanded
        } else if activityCount > 0 {
            state = .activity
        } else if isHovered {
            state = .peek
        } else {
            state = .hidden
        }
    }
}

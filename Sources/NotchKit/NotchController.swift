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

        public init(
            id: String,
            title: String,
            detail: String? = nil,
            compactText: String? = nil,
            symbolName: String? = nil,
            barFill: Double? = nil
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.compactText = compactText
            self.symbolName = symbolName
            self.barFill = barFill.map { min(1, max(0, $0)) }
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

    /// True while a volume/brightness HUD is the one and only live activity —
    /// the case that gets the wider `NotchMetrics.hud` island and the
    /// glyph + label ear layout. `activityCount`, not `activities.count`:
    /// overflow counts as company too.
    public var isSoloHUD: Bool {
        activityCount == 1 && activities.first?.id == Self.hudActivityID
    }

    public var parameters: NotchShapeParameters {
        switch state {
        case .hidden:
            return metrics.collapsed
        case .peek:
            return metrics.peek
        case .activity:
            if activityCount >= 2 { return metrics.twoActivities }
            return isSoloHUD ? metrics.hud : metrics.oneActivity
        case .expanded:
            return metrics.expanded
        }
    }

    public func setHovered(_ hovered: Bool) {
        isHovered = hovered
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
        state = .expanded
    }

    public func dismiss() {
        guard state == .expanded else { return }
        state = .hidden          // recomputeState restores peek/activity if warranted
        recomputeState()
    }

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
    }

    /// Forwards a panel-originated command out to `onIntent`. Public so the
    /// view layer (`MediaPanelView`, `NotchRootView`'s ears) can call it
    /// without knowing who — if anyone — is listening.
    public func emit(_ intent: NotchIntent) {
        onIntent?(intent)
    }

    /// An open panel outranks everything; otherwise activities outrank hover,
    /// and hover outranks nothing at all.
    private func recomputeState() {
        if state == .expanded { return }
        if activityCount > 0 {
            state = .activity
        } else if isHovered {
            state = .peek
        } else {
            state = .hidden
        }
    }
}

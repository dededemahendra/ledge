import Foundation

/// Turns a trackpad's horizontal scroll gesture over the island into one
/// skip per swipe (the reference app's "swipe left or right to switch
/// songs", 2026-09-29). Pure: `NotchPresenter` feeds it the scroll
/// events' deltas and phases.
///
/// Fires ONCE per gesture, the moment the accumulated finger travel
/// crosses `threshold`, then stays quiet until the fingers lift — so a long
/// swipe never skips twice, and the momentum tail after lift-off (which
/// arrives as its own phase) is ignored entirely. Finger left is next,
/// finger right is previous, regardless of the natural-scrolling
/// setting: with natural scrolling off the device reports the delta
/// inverted, and `invertedFromDevice` says which way to read it.
public struct SwipeToSkipTracker: Sendable {
    public enum Direction: Sendable, Equatable {
        case next, previous
    }

    public enum Phase: Sendable, Equatable {
        case began, changed, ended, momentum, none
    }

    /// Finger travel, in points, that commits a skip. Deliberate enough
    /// that a brush over the island does nothing, short enough that a
    /// flick lands.
    public static let threshold: CGFloat = 50

    private var accumulated: CGFloat = 0
    private var fired = false

    public init() {}

    public mutating func track(deltaX: CGFloat, phase: Phase, invertedFromDevice: Bool) -> Direction? {
        switch phase {
        case .began:
            accumulated = 0
            fired = false
            return nil
        case .ended, .none, .momentum:
            if phase != .momentum { accumulated = 0; fired = false }
            return nil
        case .changed:
            guard !fired else { return nil }
            // Natural scrolling reports the delta in the finger's own
            // direction; the classic setting reports it inverted.
            let finger = invertedFromDevice ? deltaX : -deltaX
            accumulated += finger
            guard abs(accumulated) >= Self.threshold else { return nil }
            fired = true
            return accumulated < 0 ? .next : .previous
        }
    }
}

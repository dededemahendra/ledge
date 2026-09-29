import Foundation

/// Hover intent for the island (2026-09-29): the pointer has to DWELL on
/// the island before it counts as hovering, so a cursor passing through
/// the notch on its way to the menu bar does not flash the panel open.
/// Leaving counts at once — the island must never hang on after the
/// cursor has gone.
///
/// Pure and clock-fed, like `SwipeToSkipTracker`: the presenter feeds it
/// the geometric fact on every mouse move, every 250 ms tick, and when
/// its dwell timer fires, and acts on what changed. `NotchController`'s
/// `isHovered` only ever sees the promoted value; mouse acceptance follows
/// the raw `isPointerInside`, so a click during the dwell still lands.
public struct HoverIntentTracker: Sendable, Equatable {
    public enum Change: Sendable, Equatable {
        case none
        /// The dwell elapsed with the pointer still on the island.
        case hovered
        /// The pointer left a hovered island.
        case unhovered
    }

    public let dwell: TimeInterval
    /// When the pointer arrived, while the dwell is still running.
    private var enteredAt: Date?
    /// The promoted state — what the controller has been told.
    public private(set) var isHovering = false
    /// The geometric fact, promoted or not.
    public private(set) var isPointerInside = false

    public init(dwell: TimeInterval) {
        self.dwell = dwell
    }

    /// Feed the geometric fact at `now`. Returns what the controller must
    /// be told, if anything.
    public mutating func pointer(inside: Bool, at now: Date) -> Change {
        isPointerInside = inside
        guard inside else {
            enteredAt = nil
            guard isHovering else { return .none }
            isHovering = false
            return .unhovered
        }
        if isHovering { return .none }
        guard let enteredAt else {
            self.enteredAt = now
            return dwell <= 0 ? promote() : .none
        }
        guard now.timeIntervalSince(enteredAt) >= dwell else { return .none }
        return promote()
    }

    private mutating func promote() -> Change {
        enteredAt = nil
        isHovering = true
        return .hovered
    }

    /// When the running dwell elapses — the presenter's cue to check back
    /// exactly then, since a perfectly still cursor sends no more mouse
    /// events. `nil` when nothing is pending.
    public var pendingUntil: Date? {
        enteredAt.map { $0.addingTimeInterval(dwell) }
    }

    /// Forget everything (the screen was rebuilt under the cursor).
    public mutating func reset() {
        enteredAt = nil
        isHovering = false
        isPointerInside = false
    }
}

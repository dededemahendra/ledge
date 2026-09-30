import Foundation

/// What the user just did to playback, shown before the player confirms
/// it (2026-09-30): a play/pause flip, a seek, a skip. Applied over the
/// adapter's last report until the adapter reports something at least as
/// new — or for two seconds, whichever comes first — so the card moves the
/// instant the user acts instead of a few hundred milliseconds later, and
/// an unrelated report in between (artwork, say) cannot snap it back.
public struct PositionOverride: Sendable, Equatable {
    public static let lifetime: TimeInterval = 2

    public let elapsedTime: Double
    public let timestamp: Date
    public let playing: Bool

    public init(elapsedTime: Double, timestamp: Date, playing: Bool) {
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.playing = playing
    }

    public func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(timestamp) < Self.lifetime
    }

    /// The adapter has reported a position from at or after the action:
    /// its word wins from here.
    public func isSuperseded(by payload: MediaPayload) -> Bool {
        guard let reported = payload.timestamp else { return false }
        return reported >= timestamp
    }
}

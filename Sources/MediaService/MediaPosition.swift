import Foundation

/// Extrapolates playback position locally, so the adapter is never polled.
///
/// The adapter reports `elapsedTime` as it was at `timestamp`; everything after
/// that is arithmetic.
public enum MediaPosition {
    public static func elapsed(
        at now: Date,
        elapsedTime: Double,
        timestamp: Date,
        rate: Double,
        duration: Double?
    ) -> Double {
        let advanced = elapsedTime + now.timeIntervalSince(timestamp) * rate
        let floored = max(0, advanced)
        guard let duration, duration > 0 else { return floored }
        return min(floored, duration)
    }
}

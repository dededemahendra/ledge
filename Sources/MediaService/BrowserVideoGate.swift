import Foundation

/// When a browser may hold the island (2026-11-18, user's call). The
/// browser is only ever named, never the site, so the rules are about how
/// the playback behaves:
///
/// 1. It is playing. A tab that only made sound last, paused, never brings
///    the card up.
/// 2. It has a length. A video has a running time; a call or a live
///    stream reports none.
/// 3. No call is on the island. A Meet tab stays on the call card.
///
/// Once shown, a paused video keeps its card for `pausedHold`, then goes.
public enum BrowserVideoGate {
    public static let pausedHold: TimeInterval = 120
    /// When to ask again after a pause: a second past the hold, so a wake a
    /// hair early still finds it spent rather than leaving the card up.
    public static let recheckDelay: TimeInterval = pausedHold + 1

    public static func admits(_ payload: MediaPayload, isShowing: Bool, pausedSince: Date?, onCall: Bool, now: Date) -> Bool {
        guard !onCall else { return false }
        guard let duration = payload.duration, duration.isFinite, duration > 0 else { return false }
        if payload.isPlaying { return true }
        guard isShowing, let pausedSince else { return false }
        return now.timeIntervalSince(pausedSince) < pausedHold
    }
}

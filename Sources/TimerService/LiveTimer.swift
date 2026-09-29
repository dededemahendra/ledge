import Foundation

/// A timer or stopwatch as a pure value (2026-09-29, the island's own
/// live activity): started, paused and resumed against dates the caller
/// passes in, so it is testable without a clock and re-derived on every
/// tick. A countdown counts `duration` down; a stopwatch counts up.
public struct LiveTimer: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case countdown(TimeInterval)
        case stopwatch
    }

    public let kind: Kind
    /// Time accumulated before the current run (across pauses).
    private var banked: TimeInterval = 0
    /// When the current run began; `nil` while paused.
    private var runningSince: Date?

    public init(kind: Kind, at now: Date) {
        self.kind = kind
        runningSince = now
    }

    public var isPaused: Bool { runningSince == nil }

    public var isStopwatch: Bool {
        if case .stopwatch = kind { return true }
        return false
    }

    public func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// Seconds left on a countdown, never below zero; `nil` for a stopwatch.
    public func remaining(at now: Date) -> TimeInterval? {
        guard case .countdown(let duration) = kind else { return nil }
        return max(0, duration - elapsed(at: now))
    }

    public func isFinished(at now: Date) -> Bool {
        guard let remaining = remaining(at: now) else { return false }
        return remaining <= 0
    }

    /// The ring: 1 with the whole countdown ahead, 0 at the end. `nil` for
    /// a stopwatch, which has no end to measure against.
    public func fraction(at now: Date) -> Double? {
        guard case .countdown(let duration) = kind, duration > 0, let remaining = remaining(at: now) else { return nil }
        return max(0, min(1, remaining / duration))
    }

    public mutating func pause(at now: Date) {
        guard let since = runningSince else { return }
        banked += max(0, now.timeIntervalSince(since))
        runningSince = nil
    }

    public mutating func resume(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    public mutating func togglePause(at now: Date) {
        isPaused ? resume(at: now) : pause(at: now)
    }

    /// The trailing ear's text. A countdown rounds UP (4.2 s left reads
    /// "0:05", and "0:00" arrives exactly at the end, as on the phone); a
    /// stopwatch rounds down.
    public func displayText(at now: Date) -> String {
        switch kind {
        case .countdown: return Self.format(seconds: (remaining(at: now) ?? 0).rounded(.up))
        case .stopwatch: return Self.format(seconds: elapsed(at: now).rounded(.down))
        }
    }

    /// "12:34" under an hour, "1:02" (hours:minutes) from an hour up — the
    /// ear holds five characters, not seven.
    public static func format(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 3600 { return String(format: "%d:%02d", total / 60, total % 60) }
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }
}

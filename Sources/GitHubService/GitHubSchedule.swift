import Foundation

/// How a round went, for the schedule (2026-10-22).
public enum GitHubOutcome: Sendable, Equatable {
    case ok(anythingRunning: Bool)
    case unauthorised
    case rateLimited(until: Date)
    case unavailable
}

public enum GitHubSchedule {
    public static let idle: TimeInterval = 60
    public static let busy: TimeInterval = 20
    public static let backoff: [TimeInterval] = [60, 120, 300]

    /// Seconds until the next round, or `nil` to stop until the user tries
    /// again. `failures` counts unavailable rounds in a row, this one
    /// included.
    public static func delay(after outcome: GitHubOutcome, failures: Int, now: Date) -> TimeInterval? {
        switch outcome {
        case .ok(let running): return running ? busy : idle
        case .unauthorised: return nil
        case .rateLimited(let until): return max(idle, until.timeIntervalSince(now))
        case .unavailable: return backoff[min(max(failures, 1), backoff.count) - 1]
        }
    }
}

import Foundation

public enum ExitReason: Sendable, Equatable {
    case clean
    case signalled(Int32)
    case nonZero(Int32)
}

public enum RestartDecision: Sendable, Equatable {
    case restart(after: TimeInterval)
    case giveUp(reason: String)
}

/// Decides whether a dead adapter process should be revived.
///
/// The adapter's README is explicit: *"You should not reinvoke the script when a
/// fatal error occurs (non-zero exit code)"*. So exit reason, not just count,
/// determines the outcome: a non-zero exit is fatal and permanent, while a
/// clean exit or a signal is treated as a transient blip worth retrying with
/// exponential backoff, up to a point.
public struct RestartPolicy: Sendable {
    public static let maximumRapidFailures = 5
    public static let backoffCap: TimeInterval = 30

    private var attempts = 0
    private var fatal = false

    public init() {}

    public static func backoff(attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let delay = 0.5 * pow(2, Double(attempt - 1))
        return min(delay, backoffCap)
    }

    /// How long to wait before PROBING again after a give-up. Distinct from
    /// `backoff` on purpose: that one paces reinvocations of a process that
    /// keeps exiting; this one paces a capability test (the adapter's own
    /// `test` command) after the README's "do not reinvoke on a fatal
    /// error" has been honoured. Nothing is reinvoked until the probe
    /// passes, so this can be generous — a minute, doubling to ten.
    public static let recoveryFloor: TimeInterval = 60
    public static let recoveryCap: TimeInterval = 600

    public static func recoveryDelay(attempt: Int) -> TimeInterval {
        let delay = recoveryFloor * pow(2, Double(max(0, attempt - 1)))
        return min(delay, recoveryCap)
    }

    /// Call after the adapter has produced usable output, so a long healthy run
    /// does not count earlier stumbles against it.
    public mutating func noteHealthy() {
        attempts = 0
    }

    public mutating func decide(_ reason: ExitReason) -> RestartDecision {
        if fatal {
            return .giveUp(reason: "adapter previously failed fatally; not reinvoking")
        }

        switch reason {
        case .nonZero(let status):
            fatal = true
            return .giveUp(reason: "adapter exited with status \(status); not reinvoking")

        case .clean, .signalled:
            attempts += 1
            guard attempts <= Self.maximumRapidFailures else {
                return .giveUp(
                    reason: "adapter restarted \(Self.maximumRapidFailures) times without settling"
                )
            }
            return .restart(after: Self.backoff(attempt: attempts))
        }
    }
}

import Foundation

/// The Clock app's timers and stopwatches, as its daemon (`mobiletimerd`)
/// persists them in the `com.apple.mobiletimerd` preference domain
/// (2026-09-29). Private layout, observed on macOS 27 and written up in
/// `docs/private-api-notes.md`: a timer is `$MTTimer` with `MTTimerState`
/// (1 idle, 3 running, 2 paused — the last inferred), `MTTimerDuration`,
/// `MTTimerTitle` and `MTTimerFireTime`, which is a `$MTTimerDate` with an
/// absolute `MTTimerTimeDate` while running and a `$MTTimerTimeInterval`
/// otherwise. Anything of another shape is skipped, never guessed at.
public struct ClockTimer: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        case running(fireDate: Date)
        case paused(remaining: TimeInterval)
    }

    public let id: String
    /// The user's own name for it; `nil` for the Clock's placeholders.
    public let title: String?
    public let duration: TimeInterval
    public let state: State

    public init(id: String, title: String?, duration: TimeInterval, state: State) {
        self.id = id
        self.title = title
        self.duration = duration
        self.state = state
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running(let fireDate): return max(0, fireDate.timeIntervalSince(now))
        case .paused(let remaining): return max(0, remaining)
        }
    }

    /// Rang and not yet dismissed: the daemon keeps it running past its
    /// fire date until the user stops it.
    public func hasFired(at now: Date) -> Bool {
        if case .running(let fireDate) = state { return fireDate <= now }
        return false
    }

    public func fraction(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, remaining(at: now) / duration))
    }
}

/// `$MTStopwatch`: `MTStopwatchState` (0 reset, 1 stopped — both observed),
/// `MTStopwatchOffset`
/// (time banked before the current run) and, while running, a date the
/// run started from — read as the first `Date` value in the record, since
/// the key has not been observed yet. See `ClockTimerSnapshot.oddities`.
public struct ClockStopwatch: Sendable, Equatable, Identifiable {
    public let id: String
    public let banked: TimeInterval
    public let runningSince: Date?

    public init(id: String, banked: TimeInterval, runningSince: Date?) {
        self.id = id
        self.banked = banked
        self.runningSince = runningSince
    }

    public var isRunning: Bool { runningSince != nil }

    public func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

/// One read of the daemon's domain. Pure: built from the dictionary the
/// observer fetches, so it is testable from a fixture.
public struct ClockTimerSnapshot: Sendable, Equatable {
    public let timers: [ClockTimer]
    public let stopwatches: [ClockStopwatch]
    /// Records that did not parse, described for the log — the private
    /// layout may move under us, and this is how that gets noticed.
    public let oddities: [String]

    public static let empty = ClockTimerSnapshot(timers: [], stopwatches: [], oddities: [])

    public init(timers: [ClockTimer], stopwatches: [ClockStopwatch], oddities: [String]) {
        self.timers = timers
        self.stopwatches = stopwatches
        self.oddities = oddities
    }

    public init(domain: [String: Any]) {
        var timers: [ClockTimer] = []
        var stopwatches: [ClockStopwatch] = []
        var oddities: [String] = []

        let timerRecords = ((domain["MTTimers"] as? [String: Any])?["MTTimers"] as? [[String: Any]]) ?? []
        for wrapper in timerRecords {
            guard let record = wrapper["$MTTimer"] as? [String: Any],
                  let id = record["MTTimerID"] as? String,
                  let state = (record["MTTimerState"] as? NSNumber)?.intValue,
                  let duration = (record["MTTimerDuration"] as? NSNumber)?.doubleValue
            else { oddities.append("timer: \(wrapper.keys.sorted())"); continue }
            let rawTitle = (record["MTTimerTitle"] as? String) ?? ""
            let title = (rawTitle.isEmpty || rawTitle == "CURRENT_TIMER") ? nil : rawTitle
            let fire = record["MTTimerFireTime"] as? [String: Any]
            switch state {
            case 1:
                continue   // idle: a preset in the list, nothing to show
            case 3:
                if let date = (fire?["$MTTimerDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date {
                    timers.append(ClockTimer(id: id, title: title, duration: duration, state: .running(fireDate: date)))
                } else {
                    oddities.append("timer \(id) state 3 without a fire date: \(fire?.keys.sorted() ?? [])")
                }
            case 2:
                if let interval = ((fire?["$MTTimerTimeInterval"] as? [String: Any])?["MTTimerTimeInterval"] as? NSNumber)?.doubleValue {
                    timers.append(ClockTimer(id: id, title: title, duration: duration, state: .paused(remaining: interval)))
                } else {
                    oddities.append("timer \(id) state 2 without an interval: \(fire?.keys.sorted() ?? [])")
                }
            default:
                oddities.append("timer \(id) state \(state): \(record.keys.sorted())")
            }
        }

        let watchRecords = ((domain["MTStopwatches"] as? [String: Any])?["MTStopwatches"] as? [[String: Any]]) ?? []
        for wrapper in watchRecords {
            guard let record = wrapper["$MTStopwatch"] as? [String: Any],
                  let id = record["MTStopwatchIdentifier"] as? String,
                  let state = (record["MTStopwatchState"] as? NSNumber)?.intValue
            else { oddities.append("stopwatch: \(wrapper.keys.sorted())"); continue }
            let banked = (record["MTStopwatchOffset"] as? NSNumber)?.doubleValue ?? 0
            let date = record.values.compactMap { $0 as? Date }.first
            switch state {
            case 0, 1:
                continue   // reset, stopped: nothing to show
            default:
                if let date {
                    stopwatches.append(ClockStopwatch(id: id, banked: banked, runningSince: date))
                } else {
                    oddities.append("stopwatch \(id) state \(state) without a date: \(record.keys.sorted())")
                }
            }
        }

        self.init(timers: timers, stopwatches: stopwatches, oddities: oddities)
    }

    /// The one the island shows: the running timer that fires soonest,
    /// else a paused one, else a running stopwatch.
    public enum Featured: Sendable, Equatable {
        case timer(ClockTimer)
        case stopwatch(ClockStopwatch)
    }

    public func featured(at now: Date) -> Featured? {
        if let running = timers.filter(\.isRunning).min(by: { $0.remaining(at: now) < $1.remaining(at: now) }) {
            return .timer(running)
        }
        if let paused = timers.first(where: { !$0.isRunning }) { return .timer(paused) }
        if let watch = stopwatches.first(where: \.isRunning) { return .stopwatch(watch) }
        return nil
    }
}

/// Reads the daemon's domain through cfprefsd once a second — the same
/// place the daemon writes, so no disk lag — and keeps the latest
/// snapshot. No notification name for changes was found, and at this size
/// a poll costs nothing.
@MainActor
public final class ClockTimerObserver {
    public static let domain = "com.apple.mobiletimerd"
    public private(set) var snapshot: ClockTimerSnapshot = .empty
    private var lastRead: Date = .distantPast

    public init() {}

    /// Re-reads if a second has passed; returns the current snapshot.
    @discardableResult
    public func refresh(at now: Date = Date()) -> ClockTimerSnapshot {
        guard now.timeIntervalSince(lastRead) >= 1 else { return snapshot }
        lastRead = now
        let id = Self.domain as CFString
        CFPreferencesAppSynchronize(id)
        let raw = CFPreferencesCopyMultiple(nil, id, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] ?? [:]
        let fresh = ClockTimerSnapshot(domain: raw)
        if fresh != snapshot { snapshot = fresh }
        return snapshot
    }
}

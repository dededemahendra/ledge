import Foundation

/// Which reads of the app's mute to believe (review, 2026-10-23). After a
/// press the app updates its title a moment later, so a read that began
/// before the press, or one that disagrees within `hold`, is not believed.
struct MuteReadGate: Sendable {
    static let hold: TimeInterval = 1.5
    private(set) var generation = 0
    private var pressed: (value: Bool, until: Date)?

    mutating func pressed(_ target: Bool, at now: Date) {
        generation += 1
        pressed = (target, now.addingTimeInterval(Self.hold))
    }

    func accepts(_ read: Bool?, startedAt generation: Int, at now: Date) -> Bool {
        guard generation == self.generation else { return false }
        if let pressed, now < pressed.until, read != pressed.value { return false }
        return true
    }
}

/// When to look at the app's mute (review, 2026-10-23): never two reads at
/// once; once a second while the control is known; after a search that
/// found nothing, 1, 2, 4, 8, then every 10 seconds, so a page without the
/// control isn't walked over and over. A new app starts again at once.
struct ReadPacer: Sendable {
    private var inFlight = false
    private var failures = 0
    private var nextAllowed = Date.distantPast

    static func wait(afterFailures failures: Int) -> TimeInterval {
        min(10, pow(2, Double(max(1, failures) - 1)))
    }

    mutating func shouldStart(at now: Date) -> Bool {
        guard !inFlight, now >= nextAllowed else { return false }
        inFlight = true
        return true
    }

    mutating func finished(found: Bool, at now: Date) {
        inFlight = false
        failures = found ? 0 : failures + 1
        nextAllowed = now.addingTimeInterval(found ? 1 : Self.wait(afterFailures: failures))
    }

    mutating func reset() { self = ReadPacer() }
}

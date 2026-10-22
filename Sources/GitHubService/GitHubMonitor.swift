import Foundation

/// The loop (2026-10-22): asks GitHub, compares with the last good answer,
/// and hands the app what it found. A round at once on `start` and on
/// `checkNow()`; between rounds it waits as `GitHubSchedule` says. The last
/// good snapshot is kept through failures, so what happened while GitHub
/// was out of reach is told once it answers again.
@MainActor
public final class GitHubMonitor {
    public enum Status: Sendable, Equatable {
        case off
        /// The first round after start.
        case checking
        case ok(at: Date)
        case signInAgain
        case rateLimited(until: Date)
        case failed(at: Date)
    }

    public private(set) var status: Status = .off
    /// The last good answer, and the baseline the next round compares with.
    public private(set) var snapshot: GitHubSnapshot?
    /// Every good round: what was found, and what happened since the last.
    public var onRound: ((GitHubSnapshot, [GitHubEvent]) -> Void)?

    private var client: GitHubClient?
    private var loop: Task<Void, Never>?
    private var failures = 0
    /// The commits whose checks have passed, so a pass is told once per
    /// commit (2026-10-22): see `GitHubEvents.between(_:_:passed:)`.
    private var passedChecks: Set<String> = []
    private let now: @MainActor () -> Date

    public init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    public var isRunning: Bool { client != nil }

    /// Starts over with `client`: the first round is a quiet baseline.
    public func start(_ client: GitHubClient) {
        prepare(client)
        restart()
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        client = nil
        snapshot = nil
        failures = 0
        passedChecks = []
        status = .off
    }

    /// A round now, then the schedule as usual. Nothing while stopped or
    /// after a 401, which needs `start` with a new client.
    public func checkNow() {
        guard client != nil, status != .signInAgain else { return }
        restart()
    }

    func prepare(_ client: GitHubClient) {
        stop()
        self.client = client
        status = .checking
    }

    private func restart() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled, let delay = await self?.round() {
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// One round; how long to wait before the next, or `nil` to stop.
    func round() async -> TimeInterval? {
        guard let client else { return nil }
        let previous = snapshot
        let result = await client.round(previous: previous, now: now())
        // Stopped, restarted or given another client while asking.
        guard !Task.isCancelled, client === self.client else { return nil }
        let outcome: GitHubOutcome
        switch result {
        case .success(let next):
            failures = 0
            snapshot = next
            status = .ok(at: next.takenAt)
            let events = GitHubEvents.between(previous, next, passed: &passedChecks)
            onRound?(next, events)
            outcome = .ok(anythingRunning: !GitHubEvents.running(in: next).isEmpty)
        case .failure(.unauthorised):
            status = .signInAgain
            outcome = .unauthorised
        case .failure(.rateLimited(let until)):
            status = .rateLimited(until: until)
            outcome = .rateLimited(until: until)
        case .failure(.unavailable):
            failures += 1
            status = .failed(at: now())
            outcome = .unavailable
        }
        return GitHubSchedule.delay(after: outcome, failures: failures, now: now())
    }
}

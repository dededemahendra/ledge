import Testing
import Foundation
@testable import MediaService

@Test func backoffDoublesAndThenCaps() {
    #expect(RestartPolicy.backoff(attempt: 1) == 0.5)
    #expect(RestartPolicy.backoff(attempt: 2) == 1.0)
    #expect(RestartPolicy.backoff(attempt: 3) == 2.0)
    #expect(RestartPolicy.backoff(attempt: 4) == 4.0)
    #expect(RestartPolicy.backoff(attempt: 50) == RestartPolicy.backoffCap)
    #expect(RestartPolicy.backoffCap == 30)
}

@Test func aCleanExitIsTransientAndRestarts() {
    var p = RestartPolicy()
    #expect(p.decide(.clean) == .restart(after: 0.5))
}

@Test func aSignalledExitIsTransientAndRestarts() {
    var p = RestartPolicy()
    #expect(p.decide(.signalled(SIGTERM)) == .restart(after: 0.5))
}

// Review Focus 5: upstream says explicitly not to reinvoke on a fatal error.
@Test func aNonZeroExitIsFatalAndNeverRetried() {
    var p = RestartPolicy()
    #expect(p.decide(.nonZero(1))
            == .giveUp(reason: "adapter exited with status 1; not reinvoking"))
}

@Test func aFatalExitStaysFatalOnSubsequentQueries() {
    var p = RestartPolicy()
    _ = p.decide(.nonZero(2))
    #expect(p.decide(.clean) != .restart(after: 0.5),
            "once fatal, a later clean exit must not resurrect the retry loop")
}

@Test func repeatedTransientFailuresEventuallyGiveUp() {
    var p = RestartPolicy()
    for attempt in 1...RestartPolicy.maximumRapidFailures {
        #expect(p.decide(.clean) == .restart(after: RestartPolicy.backoff(attempt: attempt)))
    }
    #expect(p.decide(.clean)
            == .giveUp(reason: "adapter restarted 5 times without settling"))
    #expect(RestartPolicy.maximumRapidFailures == 5)
}

@Test func successResetsTheAttemptCounter() {
    var p = RestartPolicy()
    _ = p.decide(.clean)
    _ = p.decide(.clean)
    p.noteHealthy()
    #expect(p.decide(.clean) == .restart(after: 0.5), "backoff starts over after a good run")
}

/// Recovery after a give-up is paced separately from restart backoff: a
/// minute, doubling, capped at ten — generous, because nothing is reinvoked
/// until the adapter's own `test` command passes.
@Test func recoveryDelayStartsAtAMinuteDoublesAndCaps() {
    #expect(RestartPolicy.recoveryDelay(attempt: 1) == 60)
    #expect(RestartPolicy.recoveryDelay(attempt: 2) == 120)
    #expect(RestartPolicy.recoveryDelay(attempt: 4) == 480)
    #expect(RestartPolicy.recoveryDelay(attempt: 5) == 600)
    #expect(RestartPolicy.recoveryDelay(attempt: 50) == RestartPolicy.recoveryCap)
    #expect(RestartPolicy.recoveryDelay(attempt: 0) == 60, "a bad attempt number still waits the floor")
}

/// The fatal latch belongs to the process it judged. `MediaService` builds a
/// fresh policy per `start()` and per successful recovery; this pins that a
/// fresh value really does start clean, which is what makes that reset
/// meaningful.
@Test func aFreshPolicyForgetsAnEarlierFatalExit() {
    var old = RestartPolicy()
    #expect(old.decide(.nonZero(1)) == .giveUp(reason: "adapter exited with status 1; not reinvoking"))
    var fresh = RestartPolicy()
    #expect(fresh.decide(.clean) == .restart(after: 0.5))
}

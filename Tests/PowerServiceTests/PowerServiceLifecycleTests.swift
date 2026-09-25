import Testing
import Foundation
@testable import PowerService

/// `start()` is documented as idempotent — a second call should supersede the
/// first cleanly, not leave the caller holding a stream that is already dead.
///
/// The bug this pins: `teardown()`'s `continuation?.finish()` synchronously
/// invokes the OLD stream's `onTermination` handler, which schedules
/// `Task { @MainActor in self?.stop() }`. That task runs on the main actor
/// shortly after `start()` returns — AFTER the second `start()` has already
/// installed its own continuation and run-loop source — and tears both back
/// down, silently killing power monitoring on the very first re-subscribe.
///
/// There is no seam to force a real `PowerEvent` to arrive deterministically
/// (`poll()` reads live `IOKit` power sources), so "the stream is live" is
/// tested the only honest way available: race `next()` against a timeout.
/// A dead stream's `next()` resolves to `nil` almost immediately (the
/// runaway `stop()` task above runs within one main-actor turn). A live
/// stream's `next()` either produces a real event or is still pending when
/// the timeout fires — both count as "alive". Only "resolved to `nil` before
/// the timeout" counts as the bug.
///
/// Both returned streams are kept in named `let`s for the test's whole
/// lifetime (matching how `AppModel.start()` actually uses this API — it
/// binds `let stream = power.start()` and captures it into a consuming
/// `Task` immediately). `AsyncStream`'s closure-based initializer fires its
/// OWN `onTermination(.cancelled)` the moment the returned stream value is
/// discarded without ever being consumed, independent of this class's
/// continuation bookkeeping — discarding either stream early would trip that
/// unrelated stdlib behaviour and produce a false failure here.
@MainActor
@Test func secondStartYieldsALiveStreamNotOneAlreadyTornDown() async throws {
    let service = PowerService()
    let first = service.start()
    let second = service.start()

    enum Outcome { case value(PowerEvent?), stillPending }

    let outcome = await withTaskGroup(of: Outcome.self) { group in
        group.addTask {
            var iterator = second.makeAsyncIterator()
            return .value(await iterator.next())
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(300))
            return .stillPending
        }
        let firstResult = await group.next() ?? .stillPending
        group.cancelAll()
        return firstResult
    }

    service.stop()
    _ = first   // keep alive for the whole race -- see doc comment above

    switch outcome {
    case .value(let event):
        #expect(
            event != nil,
            """
            second start()'s stream resolved to nil almost immediately — it was torn down \
            by the first stream's onTermination handler instead of staying live
            """
        )
    case .stillPending:
        break   // still open past the window -- alive, as expected
    }
}

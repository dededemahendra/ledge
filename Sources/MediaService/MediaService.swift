import Foundation
import ActivityKit
import OSLog

/// Live now-playing state and playback control.
///
/// Deliberately thin, same as `PowerService`/`HUDService`: the judgement lives
/// in `MediaStateMerger`, `MediaPosition`, `RestartPolicy` and `AdapterLocator`,
/// all built and tested independently. This wires them together and republishes
/// the merged state as one `AsyncStream`.
@MainActor
public final class MediaService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "media")

    public private(set) var availability: ServiceAvailability = .available {
        didSet { if availability != oldValue { onAvailabilityChange?(availability) } }
    }
    /// Fired on the main actor whenever `availability` changes — a give-up,
    /// a failed probe, or a later recovery — so the menu bar row can follow
    /// instead of showing launch-time text forever.
    public var onAvailabilityChange: ((ServiceAvailability) -> Void)?
    public private(set) var current = MediaPayload()

    private let locator: AdapterLocator?
    private var source: MediaRemoteSource?
    private var merger = MediaStateMerger()
    private var policy = RestartPolicy()
    private var continuation: AsyncStream<MediaPayload>.Continuation?
    private var restartTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryAttempts = 0
    private var sawUsableOutput = false

    public init(locator: AdapterLocator? = AdapterLocator.inMainBundle()) {
        self.locator = locator
    }

    public func start() -> AsyncStream<MediaPayload> {
        // Idempotent, same reasoning as PowerService.start()/HUDService.start():
        // a second call supersedes the first cleanly instead of orphaning its
        // `for await` forever (the old `continuation` would otherwise just be
        // overwritten with no `.finish()`) while leaking a second adapter
        // process. Safe to call unconditionally -- on the very first call
        // there is nothing yet to tear down (every teardown step below is
        // itself a no-op against empty/nil state).
        stop()

        return AsyncStream { continuation in
            self.continuation = continuation

            guard let locator else {
                availability = .unavailable(reason: "adapter not bundled")
                continuation.finish()
                return
            }

            let validation = locator.validate()
            guard validation.isAvailable else {
                availability = validation
                Self.log.info("media unavailable: \(validation.statusText, privacy: .public)")
                continuation.finish()
                return
            }

            // Before anything of ours is running: clear what a previous
            // instance left behind. Done here, not in `launch()`, which also
            // runs on every restart — by then our own stream would match.
            MediaRemoteSource.reapOrphans(locator: locator)

            // A fresh policy per `start()`: `RestartPolicy.fatal` is a latch
            // by design (the README's "do not reinvoke"), but it must not
            // outlive the process it judged — a second `start()` launches a
            // new one.
            policy = RestartPolicy()
            recoveryAttempts = 0
            availability = .available

            // Probe before streaming, so a broken MediaRemote entitlement is a
            // clean `unavailable` rather than a dead stream nobody notices.
            // Off the main actor's synchronous path: see `probe`'s doc
            // comment for the launch stall this used to cause. Until it
            // answers, `availability` stays at its provisional `.available`.
            probeTask = Task { @MainActor [weak self] in
                let ok = await MediaRemoteSource.probe(locator: locator)
                guard let self, !Task.isCancelled else { return }
                self.probeTask = nil
                guard ok else {
                    self.availability = .unavailable(reason: "MediaRemote access blocked")
                    Self.log.info("adapter test probe failed; media disabled, will re-probe")
                    self.scheduleRecovery()
                    return
                }
                self.launch()
            }

            continuation.onTermination = { [weak self] _ in
                // `[weak self]` on THIS closure, not the inner `Task`: this
                // closure is stored long-term on `self.continuation`, so an
                // implicit strong capture here (just to form an inner
                // `[weak self]`) would create `self -> continuation ->
                // onTermination -> self` -- a real retain cycle. Same fix as
                // PowerService.start()'s identical `onTermination` shape.
                Task { @MainActor in self?.stop() }
            }
        }
    }

    /// Fire-and-forget: a dropped playback command is not worth surfacing.
    public func send(_ command: MediaCommand) {
        guard let locator, availability.isAvailable else { return }
        MediaRemoteSource.fire(locator: locator, command: command)
    }

    public func stop() {
        probeTask?.cancel()
        probeTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        restartTask?.cancel()
        restartTask = nil
        source?.terminate()
        source = nil
        // Cleared before `finish()`: `finish()` invokes `onTermination`
        // SYNCHRONOUSLY on whichever thread calls `stop()`, and that handler
        // schedules `Task { @MainActor in self?.stop() } `. Left in place, a
        // second `start()` (which calls `stop()` on the FIRST continuation
        // before installing the second) would queue a `stop()` task that runs
        // after the second continuation and adapter process are already
        // installed -- tearing both back down and silently killing media on
        // the very first re-subscribe. The handler's only job is to react to
        // a termination this class did not itself initiate (e.g. the consumer
        // dropping the stream); a termination `stop()` itself drives needs no
        // such reaction. Same fix as PowerService.teardown()/HUDService.stop().
        continuation?.onTermination = nil
        continuation?.finish()
        continuation = nil
    }

    private func launch() {
        guard let locator else { return }
        merger.reset()          // never let a dead process's state leak forward
        sawUsableOutput = false

        let source = MediaRemoteSource(locator: locator)
        self.source = source

        source.run(
            onLine: { [weak self] line in
                Task { @MainActor [weak self] in self?.ingest(line) }
            },
            onExit: { [weak self] reason in
                Task { @MainActor [weak self] in self?.handleExit(reason) }
            }
        )
    }

    private func ingest(_ line: String) {
        guard let parsed = MediaStreamLine.parse(line) else { return }
        guard let payload = merger.apply(parsed) else { return }

        if !sawUsableOutput {
            sawUsableOutput = true
            policy.noteHealthy()   // a healthy run forgives earlier stumbles
        }
        current = payload
        continuation?.yield(payload)
    }

    private func handleExit(_ reason: ExitReason) {
        source = nil
        switch policy.decide(reason) {
        case .restart(let delay):
            Self.log.info("adapter exited (\(String(describing: reason), privacy: .public)); retrying in \(delay)s")
            restartTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.launch()
            }
        case .giveUp(let reason):
            // The stream is deliberately NOT finished here (it used to be,
            // via `stop()`): finishing it ended `AppModel`'s `for await`
            // for good, so one bad adapter exit disabled media until the
            // app was relaunched. Instead the process stays down, the
            // README's "do not reinvoke on a fatal error" is honoured, and
            // `scheduleRecovery()` waits a while before asking the adapter's
            // own `test` command whether access works again. Only a passing
            // probe launches a new process, under a fresh policy.
            availability = .unavailable(reason: reason)
            Self.log.error("media given up: \(reason, privacy: .public); will re-probe")
            scheduleRecovery()
        }
    }

    /// See `handleExit`'s give-up branch. Backoff from
    /// `RestartPolicy.recoveryDelay`; cancelled by `stop()`.
    private func scheduleRecovery() {
        guard let locator else { return }
        recoveryAttempts += 1
        let delay = RestartPolicy.recoveryDelay(attempt: recoveryAttempts)
        recoveryTask?.cancel()
        recoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            let ok = await MediaRemoteSource.probe(locator: locator)
            guard let self, !Task.isCancelled else { return }
            self.recoveryTask = nil
            guard ok else {
                Self.log.info("media re-probe failed (attempt \(self.recoveryAttempts)); backing off")
                self.scheduleRecovery()
                return
            }
            Self.log.info("media re-probe passed; relaunching adapter")
            self.policy = RestartPolicy()
            self.recoveryAttempts = 0
            self.availability = .available
            self.launch()
        }
    }
}

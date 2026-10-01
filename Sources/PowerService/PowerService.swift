import Foundation
import IOKit.ps
import ActivityKit
import OSLog

/// Watches the system power sources and emits `PowerEvent`s.
///
/// Deliberately thin: all the judgement lives in `PowerEventDeriver`.
@MainActor
public final class PowerService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "power")

    public private(set) var availability: ServiceAvailability = .available
    /// The latest reading, for the live charging state on the notch
    /// (2026-10-01); `nil` until the first one.
    public private(set) var latest: PowerSnapshot?

    private var deriver = PowerEventDeriver()
    // `nonisolated(unsafe)`: both are touched from `deinit`, which is always
    // nonisolated even for a `@MainActor` class (deallocation can happen
    // from any thread) — see `deinit`/`teardown()` below. Safe without
    // further synchronisation because by the time `deinit` runs, nothing
    // else can be concurrently touching `self`, and neither
    // `CFRunLoopRemoveSource` nor `AsyncStream.Continuation.finish()` were
    // ever actually relying on Swift's actor isolation for thread safety —
    // only reaching the stored properties from a nonisolated context needed
    // the annotation.
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    private nonisolated(unsafe) var continuation: AsyncStream<PowerEvent>.Continuation?

    public init() {}

    deinit {
        // Released without `stop()`, the run-loop source would otherwise go
        // on firing into freed memory — its callback dereferences exactly
        // the `self` this deinit is in the middle of tearing down (see
        // `Unmanaged.passUnretained(self)` below).
        teardown()
    }

    public func start() -> AsyncStream<PowerEvent> {
        // Idempotent: a second call supersedes the first cleanly instead of
        // orphaning its `for await` forever (the old `continuation` gets
        // overwritten with no `.finish()`) while leaking a second run-loop
        // source (only the latest is ever tracked, so the first is never
        // removed). Safe to call unconditionally — on the very first call
        // there is nothing yet to tear down.
        stop()

        return AsyncStream { continuation in
            self.continuation = continuation

            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
                guard let ctx else { return }
                let service = Unmanaged<PowerService>.fromOpaque(ctx).takeUnretainedValue()
                MainActor.assumeIsolated { service.poll() }
            }, context)?.takeRetainedValue() else {
                availability = .unavailable(reason: "IOPowerSources unavailable")
                Self.log.error("could not create power notification source")
                continuation.finish()
                return
            }

            runLoopSource = source
            // `.commonModes`, not `.defaultMode`: the default mode alone
            // stalls while a menu is tracking or a drag is in progress, so
            // power events would queue up silently until the user let go.
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

            continuation.onTermination = { [weak self] _ in
                // Without an explicit capture here, this closure (stored
                // long-term on `self.continuation`) implicitly captures self
                // strongly just to form the inner closure's `[weak self]`,
                // creating self -> continuation -> onTermination -> self.
                Task { @MainActor in self?.stop() }
            }

            poll()   // establish the baseline
        }
    }

    public func stop() {
        teardown()
    }

    /// The actual teardown, factored out so both `stop()` (`@MainActor`,
    /// inherited from the class) and `deinit` (always nonisolated) can
    /// reach it without an isolation mismatch — nonisolated code can always
    /// call further nonisolated code directly, and `@MainActor` code can
    /// always call a nonisolated function too, so nothing here needs
    /// `MainActor.assumeIsolated`'s runtime check (which would trap if
    /// `deinit` ever happened to run on a background thread).
    private nonisolated func teardown() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        // Clear `onTermination` before `finish()`: `finish()` invokes it
        // SYNCHRONOUSLY on whichever thread calls `teardown()`, and that
        // handler schedules `Task { @MainActor in self?.stop() }`. Left in
        // place, a second `start()` (which calls `stop()` -> `teardown()` on
        // the FIRST continuation before installing the second) would queue a
        // `stop()` task that runs after the second continuation and run-loop
        // source are already installed — tearing both back down and killing
        // power monitoring permanently. The handler's only job is to react
        // to a termination this class did not itself initiate (e.g. the
        // consumer dropping the stream); a termination `teardown()` itself
        // drives needs no such reaction.
        continuation?.onTermination = nil
        continuation?.finish()
        continuation = nil
    }

    private func poll() {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            Self.log.debug("no power sources returned")
            availability = .unavailable(reason: "no power sources reported")
            return
        }

        for source in sources {
            guard
                let raw = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any],
                // Mirrors kIOPSTypeKey/kIOPSInternalBatteryType (IOPSKeys.h)
                // as plain string literals, matching how every other IOKit
                // dictionary key in `PowerSnapshot.parse` is already
                // spelled here rather than via the imported C constants.
                // Without this filter, a connected UPS also satisfies
                // `PowerSnapshot.parse` and would shadow the real battery.
                raw["Type"] as? String == "InternalBattery",
                let snapshot = PowerSnapshot.parse(raw)
            else { continue }

            latest = snapshot
            availability = .available
            for event in deriver.events(for: snapshot) {
                Self.log.debug("power event: \(String(describing: event), privacy: .public)")
                continuation?.yield(event)
            }
            return   // internal battery is the only source we track
        }

        // No internal battery among the reported sources (a desktop Mac, or
        // a UPS-only setup): this service will never emit anything. Spec §9
        // wants that said, not left sitting at the default `.available`.
        Self.log.debug("no internal battery among reported power sources")
        availability = .unavailable(reason: "no internal battery")
    }
}

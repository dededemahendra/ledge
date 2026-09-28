import Foundation
import ActivityKit
import OSLog

/// Composes volume and brightness observation with stock-OSD suppression.
///
/// Deliberately thin, same as `PowerService`: the judgement lives in
/// `HUDEventDeriver`, `VolumeObserver`, `BrightnessObserver` and
/// `OSDSuppressor`, all built and tested independently. This just wires them
/// together and republishes their combined output as one `AsyncStream`.
@MainActor
public final class HUDService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "hud")

    public private(set) var availability: ServiceAvailability = .available

    private var deriver = HUDEventDeriver()
    private var volume: VolumeObserver?
    private var brightness: BrightnessObserver?
    private let suppressor = OSDSuppressor()
    /// The mechanism that actually keeps the stock overlay off screen on
    /// this macOS — see its doc comment. `OSDSuppressor` above is kept for
    /// the legacy helper, which older systems (and possibly other overlays)
    /// still route through; it is harmless where the helper never runs.
    private let interceptor = MediaKeyInterceptor()
    private var continuation: AsyncStream<HUDEvent>.Continuation?
    private var wantsSuppression: Bool
    private var pendingBrightness: Task<Void, Never>?
    private var lastPowerSourceChange: Date?

    /// How long after (or before) a power-source change a brightness change
    /// is treated as the display's own doing, and how long an observed
    /// change is held so a power change arriving just AFTER it can still
    /// veto it. The two events race: the dimming can be seen before IOKit
    /// reports the plug.
    public static let powerChangeVeto: TimeInterval = 3
    public static let brightnessHold: Duration = .milliseconds(300)

    public init(suppressStockOSD: Bool = true) {
        self.wantsSuppression = suppressStockOSD
    }

    public var isSuppressingStockOSD: Bool { suppressor.isSuppressing || interceptor.isActive }

    /// `.available` while the media keys are intercepted (system overlay
    /// replaced), `.needsPermission("Accessibility")` while waiting on the
    /// grant, `.unavailable` when suppression is switched off.
    public var systemHUDReplacement: ServiceAvailability { interceptor.availability }

    /// Forwarded from the interceptor so the menu bar row can follow a
    /// grant made while the app runs.
    public var onSystemHUDReplacementChange: ((ServiceAvailability) -> Void)? {
        get { interceptor.onAvailabilityChange }
        set { interceptor.onAvailabilityChange = newValue }
    }

    // `nonisolated`: a pure function of its parameters with no access to
    // actor state. Without this, `@MainActor` on the class would make it
    // implicitly async from a synchronous test context — this task's own
    // Step 1 test calls it directly from a plain, non-`@MainActor` `@Test`
    // func, exactly the reason `VolumeObserver.strategy`/`.availability(for:)`
    // and `BrightnessObserver.backend`/`.availability(for:)` are already
    // `nonisolated` for the same shape of function.
    nonisolated public static func composedAvailability(
        volume: ServiceAvailability,
        brightness: ServiceAvailability
    ) -> ServiceAvailability {
        if volume.isAvailable || brightness.isAvailable { return .available }
        return .unavailable(reason: "no volume or brightness source")
    }

    public func start() -> AsyncStream<HUDEvent> {
        // Idempotent, same reasoning as `PowerService.start()`: a second call
        // supersedes the first cleanly instead of orphaning its `for await`
        // forever and leaking a second pair of observers plus the suppressor's
        // sweep timer. Safe to call unconditionally — on the very first call
        // there is nothing yet to tear down (every teardown call below is
        // itself a no-op against empty/false state).
        stop()

        return AsyncStream { continuation in
            self.continuation = continuation

            // Always hand the system back a working helper before doing anything.
            suppressor.recoverAtLaunch()

            let volume = VolumeObserver { [weak self] reading in
                guard let self else { return }
                if let event = self.deriver.volumeChanged(
                    level: reading.level, muted: reading.muted
                ) {
                    self.continuation?.yield(event)
                }
            }
            let brightness = BrightnessObserver { [weak self] level in
                self?.handleObservedBrightness(level)
            }

            volume.onRebind = { [weak self] in self?.deriver.resetVolume() }
            interceptor.onBrightnessApplied = { [weak self] level in
                guard let self, let event = self.deriver.brightnessChanged(level: level) else { return }
                self.continuation?.yield(event)
            }

            volume.start()
            brightness.start()
            self.volume = volume
            self.brightness = brightness

            availability = Self.composedAvailability(
                volume: volume.availability, brightness: brightness.availability
            )
            Self.log.info("hud \(self.availability.statusText, privacy: .public), brightness backend \(String(describing: brightness.backend), privacy: .public)")

            if wantsSuppression, availability.isAvailable {
                suppressor.setSuppressing(true)
                interceptor.start(prompt: true)
            }

            continuation.onTermination = { [weak self] _ in
                // `[weak self]` on THIS closure, not the inner `Task`: this
                // closure is stored long-term on `self.continuation`, so an
                // implicit strong capture here (just to form an inner
                // `[weak self]`) would create `self -> continuation ->
                // onTermination -> self` — a real retain cycle, not a
                // theoretical one. Same fix as `PowerService.start()`'s
                // identical `onTermination` shape.
                Task { @MainActor in self?.stop() }
            }
        }
    }

    /// `AppModel` calls this on every power event (plug, unplug, charged,
    /// low). macOS dims the display slightly on battery and brightens it
    /// back on AC; without this, each of those showed a "Display" HUD.
    public func notePowerSourceChanged() {
        lastPowerSourceChange = Date()
        pendingBrightness?.cancel()
        pendingBrightness = nil
    }

    private var powerChangedRecently: Bool {
        guard let lastPowerSourceChange else { return false }
        return Date().timeIntervalSince(lastPowerSourceChange) < Self.powerChangeVeto
    }

    /// A brightness reading from the 10Hz poll. Three cases:
    /// - the media-key tap is active: keys report their own writes through
    ///   `onBrightnessApplied`, so an observed change is by definition not
    ///   the user's (the display's own adjustment, or Control Center's
    ///   slider, for which macOS itself shows no HUD). Re-baseline silently
    ///   so the next key press is measured from the true level.
    /// - off the sixteenths grid: the display's own doing. Silent.
    /// - on the grid: probably a key — but the return trip from battery
    ///   dimming lands back on the grid too, so hold it briefly and let a
    ///   power change just before or just after veto it.
    private func handleObservedBrightness(_ level: Double) {
        if interceptor.isActive {
            _ = deriver.brightnessChanged(level: level)
            return
        }
        guard let event = deriver.brightnessChanged(level: level) else { return }
        guard HUDEventDeriver.isOnKeyGrid(level), !powerChangedRecently else { return }
        pendingBrightness?.cancel()
        pendingBrightness = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.brightnessHold)
            guard let self, !Task.isCancelled, !self.powerChangedRecently else { return }
            self.continuation?.yield(event)
        }
    }

    public func setSuppressStockOSD(_ suppress: Bool) {
        wantsSuppression = suppress
        let on = suppress && availability.isAvailable
        suppressor.setSuppressing(on)
        if on { interceptor.start(prompt: true) } else { interceptor.stop() }
    }

    public func stop() {
        pendingBrightness?.cancel()
        pendingBrightness = nil
        interceptor.onBrightnessApplied = nil
        interceptor.stop()
        suppressor.shutdown()
        volume?.stop()
        brightness?.stop()
        volume = nil
        brightness = nil
        // Cleared before `finish()`, same fix as `PowerService.teardown()`:
        // `finish()` invokes `onTermination` SYNCHRONOUSLY on whichever thread
        // calls `stop()`, and that handler schedules `Task { self?.stop() }`.
        // Left in place, a second `start()` (which calls `stop()` on the FIRST
        // continuation before installing the second) would queue a `stop()`
        // task that runs after the second continuation and observers are
        // already installed — tearing both back down and killing the HUD
        // permanently. The handler's only job is to react to a termination
        // this class did not itself initiate; a termination `stop()` itself
        // drives needs no such reaction.
        continuation?.onTermination = nil
        continuation?.finish()
        continuation = nil
    }
}

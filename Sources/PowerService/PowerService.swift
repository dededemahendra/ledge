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

    private var deriver = PowerEventDeriver()
    private var runLoopSource: CFRunLoopSource?
    private var continuation: AsyncStream<PowerEvent>.Continuation?

    public init() {}

    public func start() -> AsyncStream<PowerEvent> {
        AsyncStream { continuation in
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
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

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
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        continuation?.finish()
        continuation = nil
    }

    private func poll() {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            Self.log.debug("no power sources returned")
            return
        }

        for source in sources {
            guard
                let raw = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any],
                let snapshot = PowerSnapshot.parse(raw)
            else { continue }

            for event in deriver.events(for: snapshot) {
                Self.log.debug("power event: \(String(describing: event), privacy: .public)")
                continuation?.yield(event)
            }
            return   // internal battery is the first source
        }
    }
}

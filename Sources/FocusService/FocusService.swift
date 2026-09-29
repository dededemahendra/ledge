import Foundation
import OSLog
import ActivityKit

/// Focus on/off as a blip (2026-09-29): polls the menu bar's extras once a
/// second through Accessibility and streams the transitions. Needs the
/// Accessibility grant; without it the menu says so, like the media keys.
@MainActor
public final class FocusService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "focus")

    public private(set) var availability: ServiceAvailability = .available
    public private(set) var current: FocusState?

    private var deriver = FocusEventDeriver()
    private var timer: Timer?
    private var continuation: AsyncStream<FocusEvent>.Continuation?

    public init() {}

    public func start() -> AsyncStream<FocusEvent> {
        let (stream, continuation) = AsyncStream<FocusEvent>.makeStream()
        self.continuation = continuation
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
        return stream
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        continuation?.finish()
        continuation = nil
    }

    private func poll() {
        guard MenuBarExtrasReader.isTrusted else {
            availability = .needsPermission("Accessibility")
            return
        }
        guard let extras = MenuBarExtrasReader.read() else {
            availability = .unavailable(reason: "menu bar not readable")
            return
        }
        availability = .available
        let state = FocusState.current(in: extras)
        current = state
        if let event = deriver.sample(state) {
            Self.log.notice("focus \(event.isOn ? "on" : "off", privacy: .public): \(event.state.name, privacy: .private)")
            continuation?.yield(event)
        }
    }
}

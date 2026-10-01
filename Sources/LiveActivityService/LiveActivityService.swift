import AppKit
import OSLog
import ActivityKit

public enum LiveActivityEvent: Sendable, Equatable {
    /// The pill is showing and these are its pixels (a new frame each
    /// time they change).
    case showing(PillFrame)
    /// The pill has gone.
    case ended
}

/// An iPhone Live Activity mirrored from the menu bar (2026-10-01): once
/// a second the pill is looked for through Accessibility; while it shows,
/// `PillCapture` screenshots it twice a second and every changed frame
/// is an event.
/// A click on the island presses the pill, and the system opens its own
/// expanded view. Needs Accessibility (the media keys' grant) to find the
/// pill and Screen Recording to read it; the first time a pill is seen
/// without the latter, the system is asked once.
@MainActor
public final class LiveActivityService {
    private nonisolated static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "live-activity")

    /// `.needsPermission("Screen Recording")` until the grant is in;
    /// `.available` while off, there being nothing to complain about.
    public private(set) var availability: ServiceAvailability = .available
    public var hasScreenAccess: Bool { CGPreflightScreenCaptureAccess() }
    public private(set) var location: PillLocation?

    private var enabled = true
    private var hasAskedForAccess = false
    private var timer: Timer?
    private var continuation: AsyncStream<LiveActivityEvent>.Continuation?
    private var capture: PillCapture?
    private var captureTask: Task<Void, Never>?

    public init() {}

    public func start() -> AsyncStream<LiveActivityEvent> {
        let (stream, continuation) = AsyncStream<LiveActivityEvent>.makeStream()
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
        endCapture()
        continuation?.finish()
        continuation = nil
    }

    /// Off: no polling, no capture, no permission prompt.
    public func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled { poll() } else { endCapture(); availability = .available }
    }

    /// Opens the system's expanded view of the activity.
    public func press() {
        guard let location else { return }
        if !PillLocator.press(location) {
            Self.log.notice("live activity: press failed")
        }
    }

    private func poll() {
        guard enabled else { return }
        guard PillLocator.isTrusted else {
            availability = .needsPermission("Accessibility")
            endCapture()
            return
        }
        guard let found = PillLocator.find() else {
            availability = hasScreenAccess ? .available : .needsPermission("Screen Recording")
            endCapture()
            return
        }
        guard hasScreenAccess else {
            availability = .needsPermission("Screen Recording")
            if !hasAskedForAccess {
                hasAskedForAccess = true
                Self.log.notice("live activity: pill showing, asking for Screen Recording")
                _ = CGRequestScreenCaptureAccess()
            }
            endCapture()
            return
        }
        availability = .available
        guard found != location else { return }
        let isNew = location == nil
        location = found
        if isNew {
            Self.log.notice("live activity: pill at \(Int(found.frame.minX), privacy: .public),\(Int(found.frame.minY), privacy: .public) \(Int(found.frame.width), privacy: .public)x\(Int(found.frame.height), privacy: .public)")
        }
        let capture = self.capture ?? PillCapture { [weak self] frame in
            Task { @MainActor in self?.deliver(frame) }
        }
        self.capture = capture
        let scale = CaptureGeometry.scale(at: CGPoint(x: found.frame.midX, y: found.frame.midY))
        let frame = found.frame
        let slots = found.slots
        chain {
            do {
                try await capture.capture(frame: frame, slots: slots, scale: scale)
            } catch {
                Self.log.notice("live activity: capture failed — \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func deliver(_ frame: PillFrame) {
        guard location != nil else { return }
        continuation?.yield(.showing(frame))
    }

    private func endCapture() {
        guard location != nil || capture != nil else { return }
        let hadPill = location != nil
        location = nil
        if let capture {
            self.capture = nil
            chain { await capture.stop() }
        }
        if hadPill {
            Self.log.notice("live activity: pill gone")
            continuation?.yield(.ended)
        }
    }

    /// Capture calls run one after another, in order, off the main actor.
    private func chain(_ work: @escaping @Sendable () async -> Void) {
        let previous = captureTask
        captureTask = Task {
            await previous?.value
            await work()
        }
    }
}

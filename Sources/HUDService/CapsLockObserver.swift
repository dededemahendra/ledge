import Foundation
import CoreGraphics

/// Caps Lock, by value: the combined session modifier state, polled at
/// 10Hz like brightness. `CGEventSource.flagsState` needs no permission
/// and no event delivery — it is the same call the system uses to answer
/// "is Caps Lock on right now" — so this works with or without the
/// Accessibility grant the key tap needs.
@MainActor
public final class CapsLockObserver {
    nonisolated public static let pollInterval: TimeInterval = 0.1

    private let onChange: (Bool) -> Void
    private var timer: Timer?
    private var lastSeen: Bool?

    public init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    nonisolated public static func isCapsLockOn() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    public func start() {
        guard timer == nil else { return }
        let poll = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        poll.tolerance = Self.pollInterval / 2
        RunLoop.main.add(poll, forMode: .common)   // keeps ticking while a menu is open
        timer = poll
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let on = Self.isCapsLockOn()
        guard lastSeen != on else { return }
        lastSeen = on
        onChange(on)
    }
}

import Foundation

/// Tells the presenter when the screen locks and unlocks, via the two
/// distributed notifications `loginwindow` posts (spec §7, LockScreenService).
/// No permission, no polling.
@MainActor
public final class LockScreenObserver {
    nonisolated public static let lockedNotification = Notification.Name("com.apple.screenIsLocked")
    nonisolated public static let unlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    private let onChange: (Bool) -> Void
    private var tokens: [NSObjectProtocol] = []

    public init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    /// `true` for the lock notification, `false` for unlock, `nil` for
    /// anything else. Pure, pinned by `LockScreenObserverTests`.
    nonisolated public static func lockedState(for name: Notification.Name) -> Bool? {
        switch name {
        case lockedNotification:   return true
        case unlockedNotification: return false
        default:                   return nil
        }
    }

    public func start() {
        guard tokens.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for name in [Self.lockedNotification, Self.unlockedNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Only the name crosses into the actor — `Notification`
                // itself is not `Sendable`.
                let name = note.name
                MainActor.assumeIsolated {
                    guard let locked = Self.lockedState(for: name) else { return }
                    self?.onChange(locked)
                }
            })
        }
    }

    public func stop() {
        let center = DistributedNotificationCenter.default()
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
    }
}

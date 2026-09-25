import Foundation

/// What an activity is about. Priority and lifetime come from the kind.
public enum ActivityKind: String, Sendable, CaseIterable, Comparable {
    case hud
    case power
    case device
    case notification
    case media

    /// Higher wins a visible slot. Values fixed by spec §7.
    public var priority: Int {
        switch self {
        case .hud:          return 100
        case .power:        return 60
        case .device:       return 50
        case .notification: return 40
        case .media:        return 10
        }
    }

    /// Seconds before the activity expires. `nil` means sticky.
    public var defaultTTL: TimeInterval? {
        switch self {
        case .hud:          return 1.5
        case .power:        return 3
        case .device:       return 3
        case .notification: return 5
        case .media:        return nil
        }
    }

    public static func < (lhs: ActivityKind, rhs: ActivityKind) -> Bool {
        lhs.priority < rhs.priority
    }
}

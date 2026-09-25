import Foundation

/// Every service reports this. The app must be correct with any subset available.
public enum ServiceAvailability: Sendable, Equatable {
    case available
    case needsPermission(String)
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }

    public var statusText: String {
        switch self {
        case .available:                 return "ready"
        case .needsPermission(let what): return "needs \(what)"
        case .unavailable(let reason):   return "unavailable — \(reason)"
        }
    }
}

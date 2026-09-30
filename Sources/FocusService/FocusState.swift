import Foundation

/// A Focus turning on or off, with the Focus itself when the database is
/// readable (Full Disk Access) and without it otherwise — then the state
/// comes from the size of `Assertions.json`, which `stat` reports freely
/// (2026-09-30): ~1.27 KB with no Focus, ~630 bytes more per assertion.
public enum FocusEvent: Sendable, Equatable {
    case on(FocusMode?)
    case off(FocusMode?)

    public var mode: FocusMode? {
        switch self {
        case .on(let m), .off(let m): return m
        }
    }

    public var isOn: Bool {
        if case .on = self { return true }
        return false
    }

    /// The Focus's own symbol when known; the moon otherwise — filled on,
    /// outlined off.
    public var symbolName: String {
        if let symbol = mode?.symbolName, !symbol.isEmpty { return symbol }
        return isOn ? "moon.fill" : "moon"
    }

    public var compactText: String { isOn ? "On" : "Off" }

    /// From the database: nothing → a Focus is on; a Focus → gone is off;
    /// one Focus → another is the new one coming on; the same is nothing.
    public static func transition(from previous: FocusMode?, to current: FocusMode?) -> FocusEvent? {
        switch (previous, current) {
        case (nil, let now?):                              return .on(now)
        case (let before?, nil):                           return .off(before)
        case (let before?, let now?) where before != now:  return .on(now)
        default:                                           return nil
        }
    }
}

/// Turns successive file sizes into events when the database itself is
/// off limits. The first sample sets the baseline silently — a Focus
/// already on at launch is not news — and only jumps of at least
/// `recordSize` count: switching Focuses rewrites at nearly the same size.
public struct FocusSizeDeriver: Sendable, Equatable {
    /// Half a record: well clear of the few bytes a rewrite can shift.
    public static let recordSize = 300

    private var last: Int?

    public init() {}

    public mutating func sample(size: Int) -> FocusEvent? {
        defer { last = size }
        guard let last else { return nil }
        let delta = size - last
        if delta >= Self.recordSize { return .on(nil) }
        if delta <= -Self.recordSize { return .off(nil) }
        return nil
    }
}

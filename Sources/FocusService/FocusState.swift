import Foundation

/// A Focus turning on or off. No name: the Focus database is behind Full
/// Disk Access, and this app reads only what it can without asking for
/// that — the SIZE of `~/Library/DoNotDisturb/DB/Assertions.json`, which
/// `stat` reports freely (2026-09-30, macOS 27). The file is rewritten on
/// every toggle; with no Focus it is ~1.27 KB, and each active assertion
/// adds ~630 bytes. The direction of a size jump is the event.
public enum FocusEvent: Sendable, Equatable {
    case on
    case off

    public var symbolName: String { self == .on ? "moon.fill" : "moon" }
    public var compactText: String { self == .on ? "On" : "Off" }
}

/// Turns successive file sizes into events. The first sample sets the
/// baseline silently — a Focus already on at launch is not news — and
/// only jumps of at least `recordSize` count: switching from one Focus to
/// another rewrites the record at nearly the same size, and that is not
/// a toggle.
public struct FocusSizeDeriver: Sendable, Equatable {
    /// Half a record: well clear of the few bytes a rewrite can shift.
    public static let recordSize = 300

    private var last: Int?

    public init() {}

    public mutating func sample(size: Int) -> FocusEvent? {
        defer { last = size }
        guard let last else { return nil }
        let delta = size - last
        if delta >= Self.recordSize { return .on }
        if delta <= -Self.recordSize { return .off }
        return nil
    }
}

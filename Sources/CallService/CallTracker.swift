import Foundation

/// Where a call stands (2026-10-22). `.ended` is told once, on the update
/// the call ends; the next is `.idle`.
public enum CallState: Sendable, Equatable {
    case idle
    case live(app: CallAppInfo, since: Date)
    case ended(app: CallAppInfo, length: TimeInterval)
}

/// Turns "which apps hold the mic right now", asked over and over, into a
/// call (2026-10-22). Pure: the clock comes in with each update.
///
/// A call starts once an app has held the mic for `startGrace`, so Siri and
/// dictation never flash one, and ends once nothing has for `endGrace`, so
/// a mic switch mid-call (AirPods connecting) neither ends it nor restarts
/// the clock. The clock counts from the first take, not from the end of the
/// wait. Several apps at once are one call; the earliest still holding is
/// the one shown. An app the user marked "Not a call" never leads, and
/// hiding the only one ends the call quietly, with no ended moment.
public struct CallTracker: Sendable {
    public static let startGrace: TimeInterval = 2
    public static let endGrace: TimeInterval = 2

    private struct Hold: Sendable {
        let app: CallAppInfo
        let firstTake: Date
        var lastSeen: Date
    }

    private struct Call: Sendable {
        let since: Date
        var shown: CallAppInfo
        var lastSeen: Date
    }

    /// Every app holding the mic or within `endGrace` of letting go, hidden
    /// ones included, so bringing one back counts from its first take.
    private var holds: [String: Hold] = [:]
    private var call: Call?

    public init() {}

    public mutating func update(now: Date, holders: [CallAppInfo], hidden: Set<String>) -> CallState {
        for app in holders {
            holds[app.bundleID] = Hold(app: app, firstTake: holds[app.bundleID]?.firstTake ?? now, lastSeen: now)
        }
        holds = holds.filter { now.timeIntervalSince($0.value.lastSeen) <= Self.endGrace }
        let visible = holds.values
            .filter { !hidden.contains($0.app.bundleID) }
            .sorted { ($0.firstTake, $0.app.bundleID) < ($1.firstTake, $1.app.bundleID) }

        guard var current = call else {
            guard let lead = visible.first(where: {
                $0.lastSeen == now && now.timeIntervalSince($0.firstTake) >= Self.startGrace
            }) else { return .idle }
            call = Call(since: lead.firstTake, shown: lead.app, lastSeen: now)
            return .live(app: lead.app, since: lead.firstTake)
        }

        if let lead = visible.first {
            current.shown = lead.app
            current.lastSeen = visible.map(\.lastSeen).max() ?? current.lastSeen
            call = current
            return .live(app: lead.app, since: current.since)
        }
        call = nil
        if hidden.contains(current.shown.bundleID), holds[current.shown.bundleID] != nil { return .idle }
        return .ended(app: current.shown, length: current.lastSeen.timeIntervalSince(current.since))
    }
}

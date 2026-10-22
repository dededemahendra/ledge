import Foundation

/// What an activity is about. Priority and lifetime come from the kind.
public enum ActivityKind: String, Sendable, CaseIterable, Comparable {
    case hud
    case power
    case device
    /// A meeting reminder (2026-09-29): outranks a charger blip — a call
    /// starting matters more than a plug going in — but not a HUD, which
    /// is the user's own key press and over in a second and a half.
    case calendar
    /// A Focus turning on or off (2026-09-29): a deliberate act or a
    /// schedule, worth a glance; under the device blip, which is a thing
    /// physically happening.
    case focus
    case notification
    /// A newer Ledge on GitHub (2026-10-22): once per version, under every
    /// other blip (it waits for nothing) and over a Clock timer.
    case update
    /// The island's own timer or stopwatch (2026-09-29): sticky while it
    /// runs, above media (a running timer is what the island is for) and
    /// below every blip, which pre-empts it for its few seconds.
    case timer
    /// An iPhone Live Activity (2026-10-01): sticky while its pill
    /// shows, above media — the phone's island too gives a new activity
    /// the stage and minimises Now Playing — and below a Clock timer,
    /// which is the user's own doing.
    case liveActivity
    case media
    /// The live charging state (2026-10-01): sticky while the charger is
    /// in, under everything — the island's resting face when nothing else
    /// is on, never in the way of music or a blip.
    case charging

    /// Higher wins a visible slot. Values fixed by spec §7.
    public var priority: Int {
        switch self {
        case .hud:          return 100
        case .power:        return 60
        case .device:       return 50
        case .calendar:     return 70
        case .focus:        return 45
        case .notification: return 40
        case .update:       return 35
        case .timer:        return 20
        case .liveActivity: return 15
        case .media:        return 10
        case .charging:     return 5
        }
    }

    /// Seconds before the activity expires. `nil` means sticky.
    public var defaultTTL: TimeInterval? {
        switch self {
        case .hud:          return 1.5
        case .power:        return 3
        case .device:       return 3
        case .calendar:     return 8       // a title and a time take longer to read than "42%"
        case .focus:        return 3
        case .notification: return 5
        case .update:       return 8       // a version and a line to read
        case .timer:        return nil
        case .liveActivity: return nil
        case .media:        return nil
        case .charging:     return nil
        }
    }

    public static func < (lhs: ActivityKind, rhs: ActivityKind) -> Bool {
        lhs.priority < rhs.priority
    }
}

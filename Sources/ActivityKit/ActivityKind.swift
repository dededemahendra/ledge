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
    /// A Claude Code session needing you, finishing or failing (2026-10-23):
    /// a few seconds, over a GitHub blip (it is waiting on you, or just
    /// ended) and under a notification, which is someone else's message.
    case agent
    /// Something on GitHub (2026-10-22): checks finished, a review, a
    /// merge, a review request. Under a notification, over the update
    /// notice.
    case github
    /// A long terminal command that finished (2026-10-23): five seconds,
    /// under a GitHub blip (someone else's doing) and over the update
    /// notice, which waits for nothing.
    case command
    /// A newer Ledge on GitHub (2026-10-22): once per version, under every
    /// other blip (it waits for nothing) and over a Clock timer.
    case update
    /// A call in any app (2026-10-22): sticky while the mic is held, over a
    /// Clock timer and music — a call is what matters while it lasts — and
    /// under every blip, which passes over it for its few seconds.
    case call
    /// A Claude Code session waiting for you (2026-10-23): sticky until you
    /// answer, over a Clock timer and music — it is stuck without you —
    /// and under a call, which is a person on the line.
    case agentWaiting
    /// The island's own timer or stopwatch (2026-09-29): sticky while it
    /// runs, above media (a running timer is what the island is for) and
    /// below every blip, which pre-empts it for its few seconds.
    case timer
    /// GitHub checks or a run of the user's going now (2026-10-22):
    /// sticky while anything runs, under a Clock timer (the user's own
    /// doing), over an iPhone Live Activity.
    case githubRun
    /// An iPhone Live Activity (2026-10-01): sticky while its pill
    /// shows, above media — the phone's island too gives a new activity
    /// the stage and minimises Now Playing — and below a Clock timer,
    /// which is the user's own doing.
    case liveActivity
    case media
    /// Claude Code sessions at work (2026-10-23): sticky while any session
    /// runs, under music because sessions work most of the day and music
    /// must still show, and over the charging face.
    case agentRun
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
        case .agent:        return 39
        case .github:       return 38
        case .command:      return 36
        case .update:       return 35
        case .call:         return 30
        case .agentWaiting: return 25
        case .timer:        return 20
        case .githubRun:    return 18
        case .liveActivity: return 15
        case .media:        return 10
        case .agentRun:     return 8
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
        case .agent:        return 8       // a word and a line to read
        case .github:       return 8       // a word and a line to read
        case .command:      return 5       // a label and a time
        case .update:       return 8       // a version and a line to read
        case .call:         return nil
        case .agentWaiting: return nil
        case .timer:        return nil
        case .githubRun:    return nil
        case .liveActivity: return nil
        case .media:        return nil
        case .agentRun:     return nil
        case .charging:     return nil
        }
    }

    /// Whether this kind may take the island's tab (2026-10-23): a sticky
    /// kind, because a blip passes in seconds and would make the tab bud and
    /// merge for nothing, and never charging, which is the island's resting
    /// face rather than a second thing going on.
    public var canSitInTab: Bool {
        defaultTTL == nil && self != .charging
    }

    public static func < (lhs: ActivityKind, rhs: ActivityKind) -> Bool {
        lhs.priority < rhs.priority
    }
}

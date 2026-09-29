import Foundation

/// One upcoming item the island might remind about: a calendar event, or
/// a reminder with a time of day (2026-09-29 — the user's day is mostly
/// timed Reminders, which Calendar shows inline but EventKit keeps behind
/// its own permission and query). Pure — no EventKit here, so the policy
/// and text below are unit-testable; the service maps `EKEvent`s and
/// `EKReminder`s into these.
public struct MeetingEvent: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case event, reminder
    }

    /// Stable per OCCURRENCE: a recurring event shares one calendar item
    /// identifier across its instances, so the start is folded in.
    public let id: String
    public let kind: Kind
    public let title: String
    public let start: Date
    /// For a reminder, `start + reminderWindow`: how long it counts as
    /// "Now" before the next item takes over.
    public let end: Date
    /// A video-call link found in the item (see `MeetingLinkDetector`), or
    /// `nil` — then a click on the blip opens Calendar or Reminders.
    public let joinURL: URL?

    /// How long a due reminder stays "Now" (it has no duration of its own).
    public static let reminderWindow: TimeInterval = 15 * 60

    public init(id: String, kind: Kind = .event, title: String, start: Date, end: Date, joinURL: URL?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.joinURL = joinURL
    }

    /// The leading ear's glyph: the calendar for an event, the checklist
    /// for a reminder — Reminders' own idiom.
    public var symbolName: String {
        kind == .event ? "calendar" : "checklist"
    }

    /// Time to the start for an ear: whole minutes rounded up under an
    /// hour ("42m"), hours and minutes above ("2h", "2h 10m"), "Now" once
    /// under way.
    public func countdownText(at now: Date) -> String {
        let remaining = start.timeIntervalSince(now)
        guard remaining > 0 else { return "Now" }
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// The caption line under the hole: "Title · 10:00".
    public func captionText(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(title) · \(formatter.string(from: start))"
    }
}

/// Where in an event's run-up a reminder fires.
public enum ReminderStage: String, Sendable, Equatable {
    /// `leadTime` before the start — "5m".
    case soon
    /// At the start — "Now".
    case now
}

public struct MeetingReminder: Sendable, Equatable {
    public let event: MeetingEvent
    public let stage: ReminderStage
    /// When the reminder was decided, so the countdown reads right even if
    /// the app launched late into the lead time ("3m", not "5m").
    public let at: Date

    public init(event: MeetingEvent, stage: ReminderStage, at: Date) {
        self.event = event
        self.stage = stage
        self.at = at
    }

    /// The trailing ear: whole minutes to the start, rounded up, or "Now".
    public var compactText: String {
        stage == .now ? "Now" : event.countdownText(at: at)
    }

    /// The caption line under the hole: "Title · 10:00".
    public func captionText(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        event.captionText(locale: locale, timeZone: timeZone)
    }
}

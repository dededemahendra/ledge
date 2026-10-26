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
    /// `nil` — then a click on the blip opens the item itself.
    public let joinURL: URL?
    /// The item in its own app — Calendar's `ical://ekevent/<id>` or
    /// Reminders' `x-apple-reminderkit://REMCDReminder/<id>` (both
    /// registered handlers on macOS 27, checked 2026-09-29) — so a click
    /// lands on the event, not on the app's last view. `nil` for an
    /// unsaved item.
    public let detailURL: URL?
    /// The calendar's or list's colour: a row's bar or ring in the card,
    /// and a reminder's ring in the ear.
    public let color: CalendarInfo.RGB?
    /// An all-day event (2026-10-26): only the card's days carry these, as
    /// chips; they never blip and never preview.
    public let isAllDay: Bool
    /// What a holiday or birthday calendar's day is, for its chip's glyph.
    public let occasion: Occasion?

    public enum Occasion: Sendable, Equatable {
        case holiday, birthday
    }

    /// How long a due reminder stays "Now" (it has no duration of its own).
    public static let reminderWindow: TimeInterval = 15 * 60

    public init(id: String, kind: Kind = .event, title: String, start: Date, end: Date, joinURL: URL?, detailURL: URL? = nil, color: CalendarInfo.RGB? = nil, isAllDay: Bool = false, occasion: Occasion? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.joinURL = joinURL
        self.detailURL = detailURL
        self.color = color
        self.isAllDay = isAllDay
        self.occasion = occasion
    }

    /// The leading ear's glyph: the calendar for an event, and for a
    /// reminder the hollow ring Reminders draws beside every item, in the
    /// list's colour (2026-10-21, user's call: the checklist read as a
    /// generic list icon).
    public var symbolName: String {
        kind == .event ? "calendar" : "circle"
    }

    /// An all-day chip's glyph, as the reference app draws them
    /// (2026-10-26): a star for a holiday, a gift for a birthday, the
    /// calendar otherwise.
    public var allDaySymbolName: String {
        switch occasion {
        case .holiday: "star.circle.fill"
        case .birthday: "gift.circle.fill"
        case nil: "calendar.circle.fill"
        }
    }

    /// An event between its start and its end: a row says "Now" for it.
    /// A reminder is never under way; it is due, then overdue.
    public func isUnderWay(at now: Date) -> Bool {
        kind == .event && start <= now && now < end
    }

    /// A reminder whose time has come, which Reminders marks in red from
    /// its own minute on. It stays listed for `reminderWindow` after.
    public func isPastDue(at now: Date) -> Bool {
        kind == .reminder && start <= now
    }

    /// Time to the start for an ear, as precise as it is near: whole
    /// minutes rounded up under an hour ("42m"), hours and minutes under
    /// three ("2h 10m"), hours alone beyond that ("9h" — nobody needs the
    /// minutes on tomorrow morning's alarm), "Now" once under way.
    public func countdownText(at now: Date) -> String {
        let remaining = start.timeIntervalSince(now)
        guard remaining > 0 else { return "Now" }
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 180 {
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return "\(Int((Double(minutes) / 60).rounded()))h"
    }

    /// The caption line under the hole. An event shows its span — "Title ·
    /// 21:00–22:00", so one under way says when it ends — and a reminder
    /// its time, "Title · 06:15". When the day differs the day is named:
    /// "Tomorrow 09:00–10:00", "Tomorrow at 06:15" (a bare time would read
    /// as this morning's); further out, the date.
    public func captionText(
        at now: Date = Date(), locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        "\(title) · \(whenText(at: now, locale: locale, timeZone: timeZone))"
    }

    /// The start time alone, for a row in the card: "22:13".
    public func startTimeText(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.timeStyle = .short
        time.dateStyle = .none
        return time.string(from: start)
    }

    /// The time alone: "21:00–22:00", "06:15", "Tomorrow 09:00–10:00",
    /// "Tomorrow at 06:15", "1 Oct 2026 09:00–10:00".
    public func whenText(
        at now: Date = Date(), locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.timeStyle = .short
        time.dateStyle = .none
        let when = kind == .event
            ? "\(time.string(from: start)) to \(time.string(from: end))"   // no dashes in what shows (user's call, 2026-10-21)
            : time.string(from: start)
        if calendar.isDate(start, inSameDayAs: now) {
            return when
        }
        // Relative to `now`, not to the wall clock (which is all
        // `doesRelativeDateFormatting` knows), so this stays testable.
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(start, inSameDayAs: tomorrow) {
            return kind == .event ? "Tomorrow \(when)" : "Tomorrow at \(when)"
        }
        let day = DateFormatter()
        day.locale = locale
        day.timeZone = timeZone
        day.dateStyle = .medium
        day.timeStyle = .none
        return "\(day.string(from: start)) \(when)"
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
        event.captionText(at: at, locale: locale, timeZone: timeZone)
    }
}

import Foundation

/// The card's days (2026-10-26, after the reference app): today in one
/// column, the next day with something on in the other. Pure, over the
/// service's `agenda`, so the grouping is unit-testable.
public enum Agenda {
    /// How many days past today the card looks for its second column.
    public static let days = 7

    /// A day's items: all-day events covering it first (a three-day trip
    /// is on each of its days), then what starts that day, in order.
    public static func items(on day: Date, in agenda: [MeetingEvent], calendar: Calendar) -> [MeetingEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let allDay = agenda.filter { $0.isAllDay && $0.start < end && $0.end > start }
        let timed = agenda.filter { !$0.isAllDay && $0.start >= start && $0.start < end }
        return allDay + timed.sorted { $0.start < $1.start }
    }

    /// The first day after `now`'s, within `days`, that has anything on;
    /// `nil` for a clear week.
    public static func nextDay(after now: Date, in agenda: [MeetingEvent], days: Int = Agenda.days, calendar: Calendar) -> (day: Date, items: [MeetingEvent])? {
        let today = calendar.startOfDay(for: now)
        for offset in 1...max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let items = items(on: day, in: agenda, calendar: calendar)
            if !items.isEmpty { return (day, items) }
        }
        return nil
    }
}

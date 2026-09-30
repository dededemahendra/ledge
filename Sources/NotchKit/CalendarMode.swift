import Foundation

/// What the card's calendar mode draws (2026-09-30, user's call: a
/// calendar, not a list): this month as a grid with today marked and a
/// dot under each day that has something, and today's own items beside
/// it. Built by `AppModel` from the calendar service; pure here.
public struct CalendarModeData: Sendable, Equatable {
    public let monthTitle: String
    /// "SEP", for the grid's corner.
    public let monthShort: String
    /// "TUE" and 30, for the big date.
    public let weekdayTitle: String
    public let dayNumber: Int
    /// Seven, starting on the calendar's first weekday.
    public let weekdaySymbols: [String]
    /// Which of the seven columns are the weekend.
    public let weekendColumns: [Bool]
    /// Rows of seven; `nil` pads the days before the 1st and after the last.
    public let weeks: [[Int?]]
    /// Today's day number when the month shown is the current one.
    public let today: Int?
    /// Days with an event or a timed reminder.
    public let markedDays: Set<Int>
    /// Today's remaining items, a few at most.
    public let items: [UpcomingEvent]

    public init(monthTitle: String, monthShort: String = "", weekdayTitle: String = "", dayNumber: Int = 0, weekdaySymbols: [String], weekendColumns: [Bool] = Array(repeating: false, count: 7), weeks: [[Int?]], today: Int?, markedDays: Set<Int>, items: [UpcomingEvent]) {
        self.monthTitle = monthTitle
        self.monthShort = monthShort
        self.weekdayTitle = weekdayTitle
        self.dayNumber = dayNumber
        self.weekdaySymbols = weekdaySymbols
        self.weekendColumns = weekendColumns
        self.weeks = weeks
        self.today = today
        self.markedDays = markedDays
        self.items = items
    }

    /// The month containing `now`, laid out by `calendar` (its first
    /// weekday, its symbols, its locale for the title).
    public init(now: Date, calendar: Calendar, markedDays: Set<Int>, items: [UpcomingEvent]) {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let short = DateFormatter()
        short.calendar = calendar
        short.locale = calendar.locale
        short.setLocalizedDateFormatFromTemplate("MMM")
        let weekday = DateFormatter()
        weekday.calendar = calendar
        weekday.locale = calendar.locale
        weekday.setLocalizedDateFormatFromTemplate("EEE")
        self.init(
            monthTitle: formatter.string(from: now),
            monthShort: short.string(from: now).uppercased(),
            weekdayTitle: weekday.string(from: now).uppercased(),
            dayNumber: calendar.component(.day, from: now),
            weekdaySymbols: (0..<7).map { symbols[($0 + first) % 7] },
            weekendColumns: (0..<7).map { let weekday = ($0 + first) % 7 + 1; return weekday == 1 || weekday == 7 },
            weeks: MonthGrid.weeks(containing: now, calendar: calendar),
            today: calendar.component(.day, from: now),
            markedDays: markedDays,
            items: items
        )
    }
}

public enum MonthGrid {
    /// The month's days in rows of seven, starting on the calendar's first
    /// weekday, `nil` where a row runs past the month's edges.
    public static func weeks(containing date: Date, calendar: Calendar) -> [[Int?]] {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        else { return [] }
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead) + range.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

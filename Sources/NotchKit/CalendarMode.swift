import Foundation

/// What the card's calendar mode draws (2026-09-30, user's call: a
/// calendar, not a list): today's date and items, and beside them the
/// next day with something on (2026-10-26, after the reference app), or
/// this month as a grid when the week ahead is clear. Built by `AppModel`
/// from the calendar service; pure here.
public struct CalendarModeData: Sendable, Equatable {
    public let monthTitle: String
    /// "SEP", for the grid's corner.
    public let monthShort: String
    /// "TUESDAY" and 30, for the big date.
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
    /// Today's remaining items.
    public let items: [UpcomingEvent]
    /// Today's all-day events, drawn as chips above the items.
    public let allDay: [UpcomingEvent]
    /// Today had items and all are over: "No more events today", not
    /// "No events today".
    public let isDayDone: Bool
    /// The next day with something on; `nil` draws the month instead.
    public let next: CalendarDay?

    public init(monthTitle: String, monthShort: String = "", weekdayTitle: String = "", dayNumber: Int = 0, weekdaySymbols: [String], weekendColumns: [Bool] = Array(repeating: false, count: 7), weeks: [[Int?]], today: Int?, markedDays: Set<Int>, items: [UpcomingEvent], allDay: [UpcomingEvent] = [], isDayDone: Bool = false, next: CalendarDay? = nil) {
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
        self.allDay = allDay
        self.isDayDone = isDayDone
        self.next = next
    }

    /// The month containing `now`, laid out by `calendar` (its first
    /// weekday, its symbols, its locale for the title).
    public init(now: Date, calendar: Calendar, markedDays: Set<Int>, items: [UpcomingEvent], allDay: [UpcomingEvent] = [], isDayDone: Bool = false, next: CalendarDay? = nil) {
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
        weekday.setLocalizedDateFormatFromTemplate("EEEE")
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
            items: items,
            allDay: allDay,
            isDayDone: isDayDone,
            next: next
        )
    }
}

/// The card's second column (2026-10-26): a day after today, under its
/// name, with its all-day chips and its items.
public struct CalendarDay: Sendable, Equatable {
    /// "TOMORROW", "WEDNESDAY, 28 OCT".
    public let title: String
    public let allDay: [UpcomingEvent]
    public let items: [UpcomingEvent]

    public init(title: String, allDay: [UpcomingEvent] = [], items: [UpcomingEvent] = []) {
        self.title = title
        self.allDay = allDay
        self.items = items
    }

    /// `date` named from `now`: "TOMORROW" for the day after, else the
    /// weekday, day and month in `calendar`'s locale.
    public init(date: Date, now: Date, calendar: Calendar, allDay: [UpcomingEvent], items: [UpcomingEvent]) {
        let title: String
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            title = "TOMORROW"
        } else {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = calendar.locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("EEEEdMMM")
            title = formatter.string(from: date).uppercased()
        }
        self.init(title: title, allDay: allDay, items: items)
    }
}

/// One line of a calendar column: an all-day chip, an item's row, or a
/// count of what did not fit.
public enum CalendarLine: Sendable, Equatable {
    case allDay(UpcomingEvent)
    case item(UpcomingEvent)
    case more(String)

    /// Up to `room` lines. When everything does not fit, the last line
    /// counts the rest ("2 more events", or "2 more all-day" when only
    /// chips are left out), and the items keep their rows ahead of the
    /// chips: they are what the day holds.
    public static func lines(allDay: [UpcomingEvent], items: [UpcomingEvent], room: Int) -> [CalendarLine] {
        guard allDay.count + items.count > room else {
            return allDay.map(CalendarLine.allDay) + items.map(CalendarLine.item)
        }
        let slots = max(0, room - 1)
        let itemsShown = min(items.count, slots)
        let allDayShown = min(allDay.count, slots - itemsShown)
        let hiddenItems = items.count - itemsShown
        let hiddenAllDay = allDay.count - allDayShown
        let summary = hiddenItems == 0
            ? "\(hiddenAllDay) more all-day"
            : hiddenItems + hiddenAllDay == 1 ? "1 more event" : "\(hiddenItems + hiddenAllDay) more events"
        return allDay.prefix(allDayShown).map(CalendarLine.allDay)
            + items.prefix(itemsShown).map(CalendarLine.item)
            + [.more(summary)]
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

import Testing
import Foundation
@testable import NotchKit

private func item(_ title: String) -> UpcomingEvent {
    UpcomingEvent(title: title, compactText: "", caption: "", time: "09:00", url: nil)
}

/// A column's lines (2026-10-26): everything when it fits; otherwise the
/// last line counts the rest, and the items keep their rows ahead of the
/// all-day chips.
@Test func aColumnThatOverflowsEndsOnACountAndKeepsItsItems() {
    let holiday = item("Holiday"), birthday = item("Birthday")
    let items = ["Standup", "Lunch", "Gym", "Read"].map(item)

    #expect(CalendarLine.lines(allDay: [holiday], items: Array(items.prefix(2)), room: 3)
            == [.allDay(holiday), .item(items[0]), .item(items[1])], "fits: all of it, chips first")
    #expect(CalendarLine.lines(allDay: [holiday], items: items, room: 4)
            == [.item(items[0]), .item(items[1]), .item(items[2]), .more("2 more events")])
    #expect(CalendarLine.lines(allDay: [holiday, birthday], items: [items[0]], room: 2)
            == [.item(items[0]), .more("2 more all-day")], "only chips left out")
    #expect(CalendarLine.lines(allDay: [holiday, birthday, item("Trip")], items: [items[0]], room: 3)
            == [.allDay(holiday), .item(items[0]), .more("2 more all-day")], "a chip takes a line the items leave")
    #expect(CalendarLine.lines(allDay: [], items: [], room: 3).isEmpty)
}

/// The second column's name: "TOMORROW" for the day after, else the
/// weekday, day and month, in capitals as the reference app writes it.
@Test func theNextDayIsNamedTomorrowOrByItsDate() {
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_ID")
    cal.timeZone = TimeZone(identifier: "Asia/Makassar")!
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 23, minute: 50))!
    let tuesday = cal.date(from: DateComponents(year: 2026, month: 10, day: 27))!
    let wednesday = cal.date(from: DateComponents(year: 2026, month: 10, day: 28))!
    #expect(CalendarDay(date: tuesday, now: now, calendar: cal, allDay: [], items: []).title == "TOMORROW")
    #expect(CalendarDay(date: wednesday, now: now, calendar: cal, allDay: [], items: []).title == "WEDNESDAY, 28 OCT")

    let data = CalendarModeData(now: now, calendar: cal, markedDays: [], items: [])
    #expect(data.weekdayTitle == "MONDAY" && data.dayNumber == 26, "the weekday spelled out over the big date")
    #expect(data.next == nil && !data.isDayDone)
}

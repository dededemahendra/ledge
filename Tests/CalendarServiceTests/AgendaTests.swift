import Testing
import Foundation
@testable import CalendarService

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Makassar")!
    return c
}()
private func date(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
}
private func timed(_ title: String, _ start: Date, kind: MeetingEvent.Kind = .event) -> MeetingEvent {
    MeetingEvent(id: title, kind: kind, title: title, start: start, end: start.addingTimeInterval(3600), joinURL: nil)
}
private func allDay(_ title: String, from: Date, days: Int = 1, occasion: MeetingEvent.Occasion? = nil) -> MeetingEvent {
    // As EventKit hands them over: midnight to the last second of the last day.
    let end = cal.date(byAdding: .day, value: days, to: from)!.addingTimeInterval(-1)
    return MeetingEvent(id: title, title: title, start: from, end: end, joinURL: nil, isAllDay: true, occasion: occasion)
}

/// A day's items (2026-10-26): its all-day events first, then what starts
/// that day in order; a trip over three days is on each of them, and
/// what starts the next day is not.
@Test func aDayListsItsAllDayEventsFirstThenItsItemsInOrder() {
    let trip = allDay("Trip", from: date(10, 25), days: 3)
    let agenda = [timed("Lunch", date(10, 26, 12)), trip, timed("Standup", date(10, 26, 9)),
                  timed("Tomorrow", date(10, 27, 0, 30)), allDay("Holiday", from: date(10, 28), occasion: .holiday)]
    #expect(Agenda.items(on: date(10, 26, 16), in: agenda, calendar: cal).map(\.title) == ["Trip", "Standup", "Lunch"])
    #expect(Agenda.items(on: date(10, 27), in: agenda, calendar: cal).map(\.title) == ["Trip", "Tomorrow"])
    #expect(Agenda.items(on: date(10, 28), in: agenda, calendar: cal).map(\.title) == ["Holiday"], "the trip ended the day before")
}

/// The card's second column: the first day after today with anything on,
/// skipping clear days, within the week.
@Test func theNextDaySkipsClearDaysAndStopsAtTheWeek() {
    let now = date(10, 26, 16, 30)
    let holiday = allDay("Hari Sumpah Pemuda", from: date(10, 28), occasion: .holiday)
    let next = Agenda.nextDay(after: now, in: [timed("Later today", date(10, 26, 18)), holiday], calendar: cal)
    #expect(next?.day == date(10, 28), "Tuesday is clear; today is never the next day")
    #expect(next?.items == [holiday])
    #expect(Agenda.nextDay(after: now, in: [timed("Far off", date(11, 3, 9))], days: 7, calendar: cal) == nil, "eight days on")
    #expect(Agenda.nextDay(after: now, in: [timed("A week on", date(11, 2, 9))], days: 7, calendar: cal)?.day == date(11, 2))
    #expect(Agenda.nextDay(after: now, in: [], calendar: cal) == nil)
}

/// An all-day chip's glyph, as the reference app draws them.
@Test func anAllDayChipsGlyphFollowsItsOccasion() {
    #expect(allDay("Holiday", from: date(10, 28), occasion: .holiday).allDaySymbolName == "star.circle.fill")
    #expect(allDay("Birthday", from: date(10, 28), occasion: .birthday).allDaySymbolName == "gift.circle.fill")
    #expect(allDay("Offsite", from: date(10, 28)).allDaySymbolName == "calendar.circle.fill")
}

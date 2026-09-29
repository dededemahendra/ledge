import Testing
import Foundation
import EventKit
@testable import CalendarService

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Makassar")!
    c.firstWeekday = 2   // Monday, as the user's calendar shows
    return c
}()
private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// The user's case: a daily 06:15 reminder left unticked this morning, asked
// at 20:43 for the next day.
@Test func aDailyRuleProjectsTomorrowFromAnOverdueDueDate() {
    let due = date(2026, 9, 29, 6, 15)
    let from = date(2026, 9, 29, 19, 43), to = date(2026, 9, 30, 20, 43)
    #expect(ReminderOccurrences.expand(due: due, rule: RecurrenceRule(frequency: .daily), from: from, to: to, calendar: cal)
            == [date(2026, 9, 30, 6, 15)])
    #expect(ReminderOccurrences.expand(due: date(2026, 9, 1, 6, 15), rule: RecurrenceRule(frequency: .daily), from: from, to: to, calendar: cal)
            == [date(2026, 9, 30, 6, 15)], "however far back it fell behind")
    #expect(ReminderOccurrences.expand(due: date(2026, 9, 29, 6, 15), rule: RecurrenceRule(frequency: .daily, interval: 2), from: from, to: to, calendar: cal)
            == [], "every other day: not tomorrow")
    #expect(ReminderOccurrences.expand(due: date(2026, 9, 28, 6, 15), rule: RecurrenceRule(frequency: .daily, interval: 2), from: from, to: to, calendar: cal)
            == [date(2026, 9, 30, 6, 15)])
}

@Test func weeklyRulesHonourNamedDaysAndTheInterval() {
    // Tue 29 Sep 2026. Weekly on Mon/Wed from a due date of Mon 21 Sep.
    let rule = RecurrenceRule(frequency: .weekly, weekdays: [2, 4])
    let from = date(2026, 9, 29, 19, 43), to = date(2026, 10, 1, 19, 43)
    #expect(ReminderOccurrences.expand(due: date(2026, 9, 21, 10, 0), rule: rule, from: from, to: to, calendar: cal)
            == [date(2026, 9, 30, 10, 0)], "Wednesday falls in the window; Monday does not")
    let fortnightly = RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [4])
    #expect(ReminderOccurrences.expand(due: date(2026, 9, 23, 10, 0), rule: fortnightly, from: from, to: to, calendar: cal)
            == [], "Wed 30 Sep is one week on, not two")
    #expect(ReminderOccurrences.expand(due: date(2026, 9, 16, 10, 0), rule: fortnightly, from: from, to: to, calendar: cal)
            == [date(2026, 9, 30, 10, 0)])
    let plainWeekly = RecurrenceRule(frequency: .weekly)
    #expect(ReminderOccurrences.expand(due: date(2026, 9, 23, 10, 0), rule: plainWeekly, from: from, to: to, calendar: cal)
            == [date(2026, 9, 30, 10, 0)], "no named days: the due date's own weekday")
}

@Test func monthlyYearlyAndTheRuleEnd() {
    let from = date(2026, 9, 29, 19, 43), to = date(2026, 9, 30, 20, 43)
    #expect(ReminderOccurrences.expand(due: date(2026, 8, 30, 20, 0), rule: RecurrenceRule(frequency: .monthly), from: from, to: to, calendar: cal)
            == [date(2026, 9, 30, 20, 0)])
    #expect(ReminderOccurrences.expand(due: date(2025, 9, 30, 9, 0), rule: RecurrenceRule(frequency: .yearly), from: from, to: to, calendar: cal)
            == [date(2026, 9, 30, 9, 0)])
    #expect(ReminderOccurrences.expand(due: date(2026, 9, 29, 6, 15), rule: RecurrenceRule(frequency: .daily, endDate: date(2026, 9, 29, 23, 59)), from: from, to: to, calendar: cal)
            == [], "the rule ended before tomorrow")
    #expect(ReminderOccurrences.expand(due: date(2026, 9, 30, 6, 15), rule: RecurrenceRule(frequency: .daily), from: from, to: to, calendar: cal)
            == [], "strictly after the due date: the due date itself is the base item, not an expansion")
}

/// End to end through EventKit objects: an unticked daily reminder from
/// this morning yields tomorrow's occurrence and not its overdue self.
@Test func anOverdueDailyReminderYieldsTomorrowsOccurrence() {
    let store = EKEventStore()
    let reminder = EKReminder(eventStore: store)
    reminder.title = "Wake Up!"
    let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    reminder.dueDateComponents = DateComponents(year: today.year, month: today.month, day: today.day, hour: 6, minute: 15)
    reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
    let now = Date()
    let items = MeetingEvent.occurrences(of: reminder, from: now, to: now.addingTimeInterval(24 * 3600))
    let due = Calendar.current.date(from: reminder.dueDateComponents!)!
    if due < now {
        #expect(items.map(\.start) == [Calendar.current.date(byAdding: .day, value: 1, to: due)!])
        #expect(items.first?.kind == .reminder && items.first?.title == "Wake Up!")
    } else {
        #expect(items.map(\.start) == [due], "run before 06:15: today's own occurrence is the upcoming one")
    }
}

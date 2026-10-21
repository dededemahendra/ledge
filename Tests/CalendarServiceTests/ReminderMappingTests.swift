import Testing
import Foundation
import EventKit
@testable import CalendarService

/// Timed reminders are items like events (2026-09-29); ones without a time
/// of day are not — there is nothing to count down to.
@Test func aTimedReminderBecomesAnItemAndAnUntimedOneIsSkipped() {
    let store = EKEventStore()
    let timed = EKReminder(eventStore: store)
    timed.title = " Exercise "
    timed.dueDateComponents = DateComponents(year: 2026, month: 9, day: 30, hour: 6, minute: 0)
    let item = MeetingEvent(ekReminder: timed)
    #expect(item?.kind == .reminder)
    #expect(item?.symbolName == "circle", "Reminders' own ring, not a list icon")
    #expect(item?.title == "Exercise")
    let due = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 6, minute: 0))!
    #expect(item?.start == due)
    #expect(item?.end == due.addingTimeInterval(MeetingEvent.reminderWindow))
    #expect(item?.detailURL?.absoluteString == "x-apple-reminderkit://REMCDReminder/\(timed.calendarItemIdentifier)",
            "a click lands on the reminder itself")

    let untimed = EKReminder(eventStore: store)
    untimed.title = "Buy milk"
    untimed.dueDateComponents = DateComponents(year: 2026, month: 9, day: 30)
    #expect(MeetingEvent(ekReminder: untimed) == nil)

    let blank = EKReminder(eventStore: store)
    blank.dueDateComponents = DateComponents(year: 2026, month: 9, day: 30, hour: 7)
    #expect(MeetingEvent(ekReminder: blank) == nil, "no title: nothing to say")
}

@Test func eventKitIdentifiersArePercentEncodedInDeepLinks() {
    #expect(MeetingEvent.detailURL(scheme: "ical://ekevent/", identifier: "AB12:CD34/RID=5")?.absoluteString
            == "ical://ekevent/AB12:CD34%2FRID=5")
}

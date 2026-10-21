import Testing
import Foundation
@testable import CalendarService

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func event(_ id: String = "standup", startingIn seconds: TimeInterval, length: TimeInterval = 1800) -> MeetingEvent {
    MeetingEvent(id: id, title: "Standup", start: t0 + seconds, end: t0 + seconds + length, joinURL: nil)
}

@Test func soonFiresOnceAtTheLeadTimeAndNowOnceAtTheStart() {
    var policy = MeetingReminderPolicy(leadTime: 300, nowWindow: 60)
    let e = event(startingIn: 600)
    #expect(policy.due(for: [e], at: t0).isEmpty, "ten minutes out: nothing yet")
    #expect(policy.nextDue(for: [e], after: t0) == t0 + 300)

    let soon = policy.due(for: [e], at: t0 + 300)
    #expect(soon.map(\.stage) == [.soon])
    #expect(soon.first?.compactText == "5m")
    #expect(policy.due(for: [e], at: t0 + 330).isEmpty, "once")
    #expect(policy.nextDue(for: [e], after: t0 + 330) == t0 + 600)

    let now = policy.due(for: [e], at: t0 + 600)
    #expect(now.map(\.stage) == [.now])
    #expect(now.first?.compactText == "Now")
    #expect(policy.due(for: [e], at: t0 + 620).isEmpty)
    #expect(policy.nextDue(for: [e], after: t0 + 620) == nil)
}

@Test func aLateLaunchGetsOneHonestReminder() {
    var policy = MeetingReminderPolicy(leadTime: 300, nowWindow: 60)
    let e = event(startingIn: 150)
    let late = policy.due(for: [e], at: t0)
    #expect(late.map(\.stage) == [.soon])
    #expect(late.first?.compactText == "3m", "two and a half minutes rounds up")

    var policy2 = MeetingReminderPolicy(leadTime: 300, nowWindow: 60)
    let started = event(startingIn: -30)
    let now = policy2.due(for: [started], at: t0)
    #expect(now.map(\.stage) == [.now], "inside the first minute: Now, and never a stale soon")
    #expect(policy2.due(for: [started], at: t0 + 10).isEmpty)

    var policy3 = MeetingReminderPolicy(leadTime: 300, nowWindow: 60)
    #expect(policy3.due(for: [event(startingIn: -120)], at: t0).isEmpty, "two minutes in: too late to be useful")
}

@Test func eachOccurrenceIsItsOwnReminderAndForgottenWhenGone() {
    var policy = MeetingReminderPolicy(leadTime: 300, nowWindow: 60)
    let a = event("a", startingIn: 300)
    let b = event("b", startingIn: 300)
    #expect(policy.due(for: [a, b], at: t0).map(\.event.id) == ["a", "b"])
    #expect(policy.due(for: [b], at: t0 + 1).isEmpty)
    // "a" left the window and came back (an edit re-added it): it may fire again.
    #expect(policy.due(for: [a], at: t0 + 2).map(\.event.id) == ["a"])
}

@Test func captionShowsTitleAndStartTimeAndNamesTheDayWhenItIsNotToday() {
    let gb = Locale(identifier: "en_GB"), utc = TimeZone(identifier: "UTC")!
    let e = MeetingEvent(id: "x", title: "Design review", start: Date(timeIntervalSince1970: 1_700_000_000), end: Date(timeIntervalSince1970: 1_700_003_600), joinURL: nil)
    let r = MeetingReminder(event: e, stage: .soon, at: e.start - 300)
    #expect(r.captionText(locale: gb, timeZone: utc) == "Design review · 22:13 to 23:13", "an event shows its span")
    #expect(e.captionText(at: e.start - 24 * 3600, locale: gb, timeZone: utc) == "Design review · Tomorrow 22:13 to 23:13")
    #expect(e.captionText(at: e.start - 3 * 24 * 3600, locale: gb, timeZone: utc) == "Design review · 14 Nov 2023 22:13 to 23:13")

    let reminder = MeetingEvent(id: "r", kind: .reminder, title: "Wake Up!", start: e.start, end: e.start + MeetingEvent.reminderWindow, joinURL: nil)
    #expect(reminder.captionText(at: e.start - 300, locale: gb, timeZone: utc) == "Wake Up! · 22:13", "a reminder has no span")
    #expect(reminder.captionText(at: e.start - 24 * 3600, locale: gb, timeZone: utc) == "Wake Up! · Tomorrow at 22:13")
}

@Test func countdownReadsMinutesThenHoursAndNowOnceStarted() {
    #expect(event(startingIn: 42 * 60).countdownText(at: t0) == "42m")
    #expect(event(startingIn: 90).countdownText(at: t0) == "2m", "rounded up")
    #expect(event(startingIn: 2 * 3600).countdownText(at: t0) == "2h")
    #expect(event(startingIn: 2 * 3600 + 10 * 60).countdownText(at: t0) == "2h 10m")
    #expect(event(startingIn: 9 * 3600 + 27 * 60).countdownText(at: t0) == "9h", "far out, hours are enough")
    #expect(event(startingIn: 9 * 3600 + 40 * 60).countdownText(at: t0) == "10h", "…to the nearest")
    #expect(event(startingIn: -60).countdownText(at: t0) == "Now")
}

/// A row in the card (2026-10-21): the start time alone, "Now" only for an
/// event under way, and a reminder past due keeps its time (drawn red).
@Test func aRowShowsTheStartTimeAndTellsUnderWayFromPastDue() {
    let gb = Locale(identifier: "en_GB"), utc = TimeZone(identifier: "UTC")!
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let e = MeetingEvent(id: "x", title: "Design review", start: start, end: start + 3600, joinURL: nil)
    #expect(e.startTimeText(locale: gb, timeZone: utc) == "22:13", "the start alone, not the span")
    #expect(!e.isUnderWay(at: start - 60))
    #expect(e.isUnderWay(at: start + 60))
    #expect(!e.isUnderWay(at: start + 3600), "over at its end")
    #expect(!e.isPastDue(at: start + 60), "an event is under way, never overdue")

    let reminder = MeetingEvent(id: "r", kind: .reminder, title: "Wake Up!", start: start, end: start + MeetingEvent.reminderWindow, joinURL: nil)
    #expect(reminder.startTimeText(locale: gb, timeZone: utc) == "22:13")
    #expect(!reminder.isPastDue(at: start - 60))
    #expect(reminder.isPastDue(at: start), "due is overdue from its own minute, as in Reminders")
    #expect(!reminder.isUnderWay(at: start + 60), "a reminder is never under way")
}

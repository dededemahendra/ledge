import Foundation
import AppKit
import EventKit
import OSLog
import ActivityKit

/// Meeting reminders from the user's calendars (2026-09-29): a blip
/// `leadTime` before an event and another at its start, with the title in
/// the island's caption line and a click that joins the call. EventKit,
/// so it needs the Calendars permission (`NSCalendarsFullAccessUsageDescription`
/// in `Info.plist.in`); asked once at launch, and a refusal shows as a
/// menu problem row rather than crashing (the Bluetooth lesson).
@MainActor
public final class CalendarService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "calendar")

    public private(set) var availability: ServiceAvailability = .available

    /// How far ahead the first reminder fires.
    public private(set) var leadTime: TimeInterval

    private let store = EKEventStore()
    private var policy: MeetingReminderPolicy
    private var events: [MeetingEvent] = []
    private var hasEvents = false
    private var hasReminders = false
    /// Calendars and lists the user switched off in Settings (2026-09-30);
    /// anything new is on until switched off.
    private var disabledCalendarIDs: Set<String> = []
    /// Days of the current month with an event / a timed reminder, for the
    /// card's month grid (2026-09-30). All-day events count here (a holiday
    /// is a mark) though they never blip.
    public private(set) var markedEventDays: Set<Int> = []
    public private(set) var markedReminderDays: Set<Int> = []
    /// The card's days (2026-10-26): from the start of today through
    /// `Agenda.days` more, all-day events included (a holiday is a chip
    /// there, though it never blips), with the timed reminders. See
    /// `Agenda` for the grouping.
    public private(set) var agenda: [MeetingEvent] = []
    /// The day the last reload ran on: a new day reloads, so the next
    /// day's events, the card's days and a new month's marks follow.
    private var loadedDay: Date?
    private var reloadTask: Task<Void, Never>?
    private var continuation: AsyncStream<MeetingReminder>.Continuation?
    private var accessTask: Task<Void, Never>?
    private var storeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var dueTimer: Timer?
    private var safetyTimer: Timer?

    public init(leadTime: TimeInterval = 5 * 60) {
        self.leadTime = leadTime
        policy = MeetingReminderPolicy(leadTime: leadTime)
    }

    public func start() -> AsyncStream<MeetingReminder> {
        let (stream, continuation) = AsyncStream<MeetingReminder>.makeStream()
        self.continuation = continuation
        accessTask = Task { @MainActor [weak self] in
            await self?.requestAccessAndBegin()
        }
        return stream
    }

    public func stop() {
        accessTask?.cancel()
        accessTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        dueTimer?.invalidate()
        dueTimer = nil
        safetyTimer?.invalidate()
        safetyTimer = nil
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        storeObserver = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        continuation?.finish()
        continuation = nil
    }

    private func requestAccessAndBegin() async {
        hasEvents = await requestAccess(to: .event)
        guard !Task.isCancelled else { return }
        hasReminders = await requestAccess(to: .reminder)
        guard !Task.isCancelled else { return }
        // `.notice`, not `.info`: persisted, so a "why no reminders?" can be
        // answered from `log show` after the fact.
        Self.log.notice("calendar access: events \(self.hasEvents, privacy: .public), reminders \(self.hasReminders, privacy: .public)")
        guard hasEvents || hasReminders else {
            availability = .needsPermission("Calendars or Reminders access (System Settings → Privacy & Security)")
            return
        }
        availability = .available

        // Any edit in Calendar (or a sync) reloads the window.
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // Timers do not fire through sleep: re-evaluate on wake so a meeting
        // that came due while the lid was shut is announced once, not missed.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // A coarse safety net under the exact timer (clock changes, a
        // missed wake notification).
        let safety = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(safety, forMode: .common)
        safetyTimer = safety
        reload()
    }

    /// Full access to one entity type: already granted, or asked for now.
    /// Each has its own prompt and its own Settings toggle.
    private func requestAccess(to entity: EKEntityType) async -> Bool {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess:
            return true
        case .notDetermined:
            do {
                return entity == .event
                    ? try await store.requestFullAccessToEvents()
                    : try await store.requestFullAccessToReminders()
            } catch {
                Self.log.error("access request failed (\(entity.rawValue, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                return false
            }
        default:
            return false
        }
    }

    /// Every calendar and reminder list the store has, for the Settings
    /// window. Empty until access is granted.
    public func availableCalendars() -> [CalendarInfo] {
        var list: [CalendarInfo] = []
        if hasEvents {
            list += store.calendars(for: .event).map { Self.info($0, kind: .event) }
        }
        if hasReminders {
            list += store.calendars(for: .reminder).map { Self.info($0, kind: .reminder) }
        }
        return list
    }

    /// Settings: which calendars to leave out. Reloads at once.
    public func setDisabledCalendars(_ ids: Set<String>) {
        guard ids != disabledCalendarIDs else { return }
        disabledCalendarIDs = ids
        if hasEvents || hasReminders { reload() }
    }

    private static func info(_ calendar: EKCalendar, kind: CalendarInfo.Kind) -> CalendarInfo {
        var color: CalendarInfo.RGB?
        if let cg = calendar.cgColor, let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
            color = CalendarInfo.RGB(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent))
        }
        return CalendarInfo(
            id: calendar.calendarIdentifier, title: calendar.title,
            source: calendar.source?.title ?? "Other", kind: kind, color: color
        )
    }

    /// The calendars a query covers: all but the disabled ones. `nil`
    /// when none are left, so the query is skipped rather than run over
    /// an empty list (which EventKit reads as "all").
    private func enabledCalendars(for entity: EKEntityType) -> [EKCalendar]? {
        let calendars = store.calendars(for: entity).filter { !disabledCalendarIDs.contains($0.calendarIdentifier) }
        return calendars.isEmpty ? nil : calendars
    }

    /// The event under way or next up, for the Settings window's previews.
    /// `nil` with nothing in the next day.
    public func nextEvent(at now: Date, allowing kinds: Set<MeetingEvent.Kind> = [.event, .reminder]) -> MeetingEvent? {
        events.first { $0.end > now && kinds.contains($0.kind) }
    }

    /// The next few under way or to come, for the call card's meetings.
    public func upcoming(at now: Date, limit: Int, allowing kinds: Set<MeetingEvent.Kind> = [.event, .reminder]) -> [MeetingEvent] {
        Array(events.lazy.filter { $0.end > now && kinds.contains($0.kind) }.prefix(limit))
    }

    /// Settings (2026-09-30): a new lead time starts a fresh policy, so a
    /// reminder already announced at five minutes may come again at ten.
    public func setLeadTime(_ seconds: TimeInterval) {
        guard seconds != leadTime else { return }
        leadTime = seconds
        policy = MeetingReminderPolicy(leadTime: seconds)
        evaluate()
    }

    /// The next day of events and timed reminders, mapped to
    /// `MeetingEvent`s. Reminders come back asynchronously, so this runs as
    /// a task; a reload arriving mid-fetch supersedes the one in flight.
    private func reload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let now = Date()
            let from = now.addingTimeInterval(-3600), to = now.addingTimeInterval(24 * 3600)
            var items: [MeetingEvent] = []
            var eventCount = 0
            if hasEvents, let calendars = enabledCalendars(for: .event) {
                let all = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: calendars))
                eventCount = all.count
                items += all.compactMap { MeetingEvent(ekEvent: $0) }
            }
            var reminderCount = 0
            if hasReminders, let lists = enabledCalendars(for: .reminder) {
                let reminders = await fetchTimedReminders(from: from, to: to, lists: lists)
                reminderCount = reminders.count
                items += reminders
            }
            // The card's days, from the start of today.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            var days: [MeetingEvent] = []
            if let daysEnd = calendar.date(byAdding: .day, value: Agenda.days + 1, to: today) {
                if hasEvents, let calendars = enabledCalendars(for: .event) {
                    days += store.events(matching: store.predicateForEvents(withStart: today, end: daysEnd, calendars: calendars))
                        .compactMap { MeetingEvent(ekEvent: $0, allowingAllDay: true) }
                }
                if hasReminders, let lists = enabledCalendars(for: .reminder) {
                    days += await fetchTimedReminders(from: today, to: daysEnd, lists: lists)
                }
            }
            // The month grid's marks.
            if let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
               let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) {
                var eventDays: Set<Int> = [], reminderDays: Set<Int> = []
                if hasEvents, let calendars = enabledCalendars(for: .event) {
                    for event in store.events(matching: store.predicateForEvents(withStart: monthStart, end: monthEnd, calendars: calendars))
                    where event.status != .canceled {
                        if let start = event.startDate { eventDays.insert(calendar.component(.day, from: start)) }
                    }
                }
                if hasReminders, let lists = enabledCalendars(for: .reminder) {
                    for item in await fetchTimedReminders(from: monthStart, to: monthEnd, lists: lists) {
                        reminderDays.insert(calendar.component(.day, from: item.start))
                    }
                }
                guard !Task.isCancelled else { return }
                markedEventDays = eventDays
                markedReminderDays = reminderDays
            }
            guard !Task.isCancelled else { return }
            events = items.filter { $0.end > now }.sorted { $0.start < $1.start }
            agenda = days.sorted { $0.start < $1.start }
            loadedDay = today
            Self.log.notice("calendar reload: \(eventCount, privacy: .public) event(s) and \(reminderCount, privacy: .public) timed reminder(s) in the next day, \(self.events.count, privacy: .public) upcoming; next: \(self.events.first?.title ?? "none", privacy: .private)")
            evaluate()
        }
    }

    /// Incomplete reminders with a time of day, as occurrences inside the
    /// window. No lower bound on the due date: a recurring reminder left
    /// unticked is due in the PAST, and only its rule says when it is next
    /// (see `ReminderOccurrences`). `fetchReminders` calls back off the
    /// main queue; only the mapped, `Sendable` values cross back.
    private func fetchTimedReminders(from: Date, to: Date, lists: [EKCalendar]) async -> [MeetingEvent] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: to, calendars: lists)
        return await withCheckedContinuation { continuation in
            // `@Sendable`, hence nonisolated: EventKit invokes this on its
            // own search queue, and a closure formed inside a @MainActor
            // method is otherwise inferred main-actor-isolated — Swift 6
            // then traps at the first isolation check inside it (crash
            // 2026-09-29 20:46, `dispatch_assert_queue_fail`).
            store.fetchReminders(matching: predicate) { @Sendable reminders in
                let items = (reminders ?? []).flatMap { MeetingEvent.occurrences(of: $0, from: from, to: to) }
                continuation.resume(returning: items)
            }
        }
    }

    private func evaluate() {
        let now = Date()
        // A new day: the window, the card's days and (on the 1st) the
        // grid's marks are for the old one.
        if let loadedDay, !Calendar.current.isDate(loadedDay, inSameDayAs: now) {
            self.loadedDay = nil
            reload()
            return
        }
        for reminder in policy.due(for: events, at: now) {
            Self.log.debug("reminder: \(reminder.stage.rawValue, privacy: .public) \(reminder.compactText, privacy: .public)")
            continuation?.yield(reminder)
        }
        armDueTimer(policy.nextDue(for: events, after: now))
    }

    private func armDueTimer(_ due: Date?) {
        if let dueTimer, dueTimer.isValid, let due, abs(dueTimer.fireDate.timeIntervalSince(due)) < 0.5 { return }
        dueTimer?.invalidate()
        dueTimer = nil
        guard let due else { return }
        let timer = Timer(fire: due, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dueTimer = timer
    }
}

extension MeetingEvent {
    /// `nil` for what is not a meeting to be reminded about: all-day
    /// events (unless `allowingAllDay`, for the card's days), cancelled
    /// ones, invitations the user declined, untitled entries.
    init?(ekEvent event: EKEvent, allowingAllDay: Bool = false) {
        guard allowingAllDay || !event.isAllDay, event.status != .canceled,
              let start = event.startDate, let end = event.endDate,
              let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return nil }
        if let me = event.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined {
            return nil
        }
        self.init(
            id: "\(event.calendarItemIdentifier)@\(Int(start.timeIntervalSince1970))",
            title: title,
            start: start,
            end: end,
            joinURL: MeetingLinkDetector.joinURL(url: event.url, location: event.location, notes: event.notes),
            detailURL: event.eventIdentifier.flatMap { Self.detailURL(scheme: "ical://ekevent/", identifier: $0) },
            color: Self.rgb(of: event.calendar),
            isAllDay: event.isAllDay,
            occasion: Self.occasion(of: event.calendar)
        )
    }

    /// The system's Birthdays calendar, and a subscribed one (which is how
    /// Calendar's holiday calendars arrive) as holidays.
    static func occasion(of calendar: EKCalendar?) -> Occasion? {
        switch calendar?.type {
        case .birthday: .birthday
        case .subscription: .holiday
        default: nil
        }
    }

    static func rgb(of calendar: EKCalendar?) -> CalendarInfo.RGB? {
        guard let cg = calendar?.cgColor, let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else { return nil }
        return CalendarInfo.RGB(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent))
    }

    /// `scheme` + the identifier, kept verbatim where a URL path allows it
    /// (UUID hyphens, the colon EventKit puts in event identifiers) and
    /// escaped where it does not (a slash would end the path).
    static func detailURL(scheme: String, identifier: String) -> URL? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return identifier.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: scheme + $0) }
    }
}

extension MeetingEvent {
    /// The reminder's occurrences inside `from...to`: its own due date when
    /// that falls in the window, plus what its recurrence rule projects
    /// into it. An overdue non-recurring reminder yields nothing — it is
    /// not upcoming.
    static func occurrences(of reminder: EKReminder, from: Date, to: Date) -> [MeetingEvent] {
        guard let base = MeetingEvent(ekReminder: reminder) else { return [] }
        var items = (base.start >= from && base.start <= to) ? [base] : []
        if let rule = reminder.recurrenceRules?.first.flatMap(RecurrenceRule.init(ekRule:)) {
            for date in ReminderOccurrences.expand(due: base.start, rule: rule, from: from, to: to) {
                items.append(MeetingEvent(
                    id: "\(reminder.calendarItemIdentifier)@\(Int(date.timeIntervalSince1970))",
                    kind: .reminder, title: base.title, start: date,
                    end: date.addingTimeInterval(reminderWindow), joinURL: base.joinURL, detailURL: base.detailURL, color: base.color
                ))
            }
        }
        return items
    }

    /// `nil` for a reminder with no time of day (nothing to count down to)
    /// or no title. Completed ones never reach here — the query asks for
    /// incomplete reminders only.
    init?(ekReminder reminder: EKReminder) {
        guard let components = reminder.dueDateComponents, components.hour != nil,
              let due = (components.calendar ?? Calendar.current).date(from: components),
              let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return nil }
        self.init(
            id: "\(reminder.calendarItemIdentifier)@\(Int(due.timeIntervalSince1970))",
            kind: .reminder,
            title: title,
            start: due,
            end: due.addingTimeInterval(Self.reminderWindow),
            joinURL: MeetingLinkDetector.joinURL(url: reminder.url, location: nil, notes: reminder.notes),
            detailURL: Self.detailURL(scheme: "x-apple-reminderkit://REMCDReminder/", identifier: reminder.calendarItemIdentifier),
            color: Self.rgb(of: reminder.calendar)
        )
    }
}

extension RecurrenceRule {
    init?(ekRule rule: EKRecurrenceRule) {
        let frequency: Frequency
        switch rule.frequency {
        case .daily:   frequency = .daily
        case .weekly:  frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly:  frequency = .yearly
        @unknown default: return nil
        }
        self.init(
            frequency: frequency,
            interval: rule.interval,
            weekdays: Set((rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue }),
            endDate: rule.recurrenceEnd?.endDate
        )
    }
}

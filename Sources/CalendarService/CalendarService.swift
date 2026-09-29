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
    public let leadTime: TimeInterval

    private let store = EKEventStore()
    private var policy: MeetingReminderPolicy
    private var events: [MeetingEvent] = []
    private var hasEvents = false
    private var hasReminders = false
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

    /// The event under way or next up, for the hover preview
    /// (`NotchController.upcoming`). `nil` with nothing in the next day.
    public func nextEvent(at now: Date) -> MeetingEvent? {
        events.first { $0.end > now }
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
            if hasEvents {
                let all = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
                eventCount = all.count
                items += all.compactMap(MeetingEvent.init(ekEvent:))
            }
            var reminderCount = 0
            if hasReminders {
                let reminders = await fetchTimedReminders(from: from, to: to)
                reminderCount = reminders.count
                items += reminders
            }
            guard !Task.isCancelled else { return }
            events = items.filter { $0.end > now }.sorted { $0.start < $1.start }
            Self.log.notice("calendar reload: \(eventCount, privacy: .public) event(s) and \(reminderCount, privacy: .public) timed reminder(s) in the next day, \(self.events.count, privacy: .public) upcoming; next: \(self.events.first?.title ?? "none", privacy: .private)")
            evaluate()
        }
    }

    /// Incomplete reminders with a time of day, as occurrences inside the
    /// window. No lower bound on the due date: a recurring reminder left
    /// unticked is due in the PAST, and only its rule says when it is next
    /// (see `ReminderOccurrences`). `fetchReminders` calls back off the
    /// main queue; only the mapped, `Sendable` values cross back.
    private func fetchTimedReminders(from: Date, to: Date) async -> [MeetingEvent] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: to, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).flatMap { MeetingEvent.occurrences(of: $0, from: from, to: to) })
            }
        }
    }

    private func evaluate() {
        let now = Date()
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
    /// events, cancelled ones, invitations the user declined, untitled
    /// entries.
    init?(ekEvent event: EKEvent) {
        guard !event.isAllDay, event.status != .canceled,
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
            joinURL: MeetingLinkDetector.joinURL(url: event.url, location: event.location, notes: event.notes)
        )
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
                    end: date.addingTimeInterval(reminderWindow), joinURL: base.joinURL
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
            joinURL: MeetingLinkDetector.joinURL(url: reminder.url, location: nil, notes: reminder.notes)
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

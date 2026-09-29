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
        var granted = false
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            granted = true
        case .notDetermined:
            do {
                granted = try await store.requestFullAccessToEvents()
            } catch {
                Self.log.error("calendar access request failed: \(error.localizedDescription, privacy: .public)")
            }
        default:
            granted = false
        }
        guard !Task.isCancelled else { return }
        // `.notice`, not `.info`: persisted, so a "why no reminders?" can be
        // answered from `log show` after the fact.
        Self.log.notice("calendar access: status \(status.rawValue, privacy: .public), granted \(granted, privacy: .public)")
        guard granted else {
            availability = .needsPermission("Calendars access (System Settings → Privacy & Security → Calendars)")
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

    /// The event under way or next up, for the hover preview
    /// (`NotchController.upcoming`). `nil` with nothing in the next day.
    public func nextEvent(at now: Date) -> MeetingEvent? {
        events.first { $0.end > now }
    }

    /// The next day of events, mapped to `MeetingEvent`s.
    private func reload() {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(24 * 3600), calendars: nil
        )
        let all = store.events(matching: predicate)
        events = all
            .compactMap(MeetingEvent.init(ekEvent:))
            .filter { $0.end > now }
            .sorted { $0.start < $1.start }
        Self.log.notice("calendar reload: \(all.count, privacy: .public) event(s) in the next day, \(self.events.count, privacy: .public) to remind about; next: \(self.events.first?.title ?? "none", privacy: .private)")
        evaluate()
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

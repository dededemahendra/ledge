import Foundation

/// Decides which reminders are due, each at most once per occurrence and
/// stage. Pure and clock-fed, like the other trackers in this package
/// family: the service feeds it the upcoming events and the time.
///
/// A launch late into the lead time still gets one reminder — "3m" if
/// there are three minutes left, "Now" inside the first minute — and
/// nothing at all once the start is more than `nowWindow` behind, when a
/// reminder would only be nagging about something already under way.
public struct MeetingReminderPolicy: Sendable, Equatable {
    public let leadTime: TimeInterval
    public let nowWindow: TimeInterval
    private var fired: Set<String> = []

    public init(leadTime: TimeInterval = 5 * 60, nowWindow: TimeInterval = 60) {
        self.leadTime = leadTime
        self.nowWindow = nowWindow
    }

    /// Reminders due at `now`. Marks them fired.
    public mutating func due(for events: [MeetingEvent], at now: Date) -> [MeetingReminder] {
        // Forget occurrences that are no longer in the window, so the set
        // never grows past the day's events.
        let live = Set(events.map(\.id))
        fired = fired.filter { key in live.contains(String(key.split(separator: "|", maxSplits: 1)[0])) }

        var reminders: [MeetingReminder] = []
        for event in events.sorted(by: { $0.start < $1.start }) {
            let sinceStart = now.timeIntervalSince(event.start)
            if sinceStart >= 0, sinceStart < nowWindow {
                // "Now" supersedes a "soon" that never fired (late launch).
                fired.insert(key(event, .soon))
                if fired.insert(key(event, .now)).inserted {
                    reminders.append(MeetingReminder(event: event, stage: .now, at: now))
                }
            } else if sinceStart < 0, -sinceStart <= leadTime {
                if fired.insert(key(event, .soon)).inserted {
                    reminders.append(MeetingReminder(event: event, stage: .soon, at: now))
                }
            }
        }
        return reminders
    }

    /// When the next reminder falls due after `now`, so the service can arm
    /// an exact timer rather than poll. `nil` when nothing is pending.
    public func nextDue(for events: [MeetingEvent], after now: Date) -> Date? {
        var candidates: [Date] = []
        for event in events {
            let soonAt = event.start.addingTimeInterval(-leadTime)
            if soonAt > now, !fired.contains(key(event, .soon)) { candidates.append(soonAt) }
            if event.start > now, !fired.contains(key(event, .now)) { candidates.append(event.start) }
        }
        return candidates.min()
    }

    private func key(_ event: MeetingEvent, _ stage: ReminderStage) -> String {
        "\(event.id)|\(stage.rawValue)"
    }
}

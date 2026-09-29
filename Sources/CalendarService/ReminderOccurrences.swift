import Foundation

/// A recurring reminder's rule, reduced to what a day-by-day expansion
/// needs. Pure — mapped from `EKRecurrenceRule` in the service.
///
/// Why this exists (2026-09-29): EventKit keeps a recurring reminder as ONE
/// object whose due date is its earliest uncompleted occurrence — a daily
/// "Wake Up!" left unticked this morning is due this morning, full stop —
/// while Calendar projects the rule forward for display. A query for
/// reminders due in the next day therefore misses every future occurrence.
/// Expanding the rule ourselves puts them back.
public struct RecurrenceRule: Sendable, Equatable {
    public enum Frequency: Sendable, Equatable {
        case daily, weekly, monthly, yearly
    }

    public let frequency: Frequency
    public let interval: Int
    /// 1 = Sunday … 7 = Saturday, for weekly rules that name days. Empty
    /// means the due date's own weekday.
    public let weekdays: Set<Int>
    public let endDate: Date?

    public init(frequency: Frequency, interval: Int = 1, weekdays: Set<Int> = [], endDate: Date? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.endDate = endDate
    }
}

public enum ReminderOccurrences {
    /// Occurrences of a reminder due at `due` under `rule`, strictly after
    /// `due`, inside `from...to`, and not past the rule's end. The time of
    /// day is the due date's own. Bounded, so a rule with a due date years
    /// back cannot spin.
    public static func expand(
        due: Date, rule: RecurrenceRule, from: Date, to: Date, calendar: Calendar = .current
    ) -> [Date] {
        guard to > from else { return [] }
        let limit = min(to, rule.endDate ?? to)
        var found: [Date] = []
        var steps = 0

        func consider(_ date: Date) {
            if date > due, date >= from, date <= limit { found.append(date) }
        }

        switch rule.frequency {
        case .weekly where !rule.weekdays.isEmpty:
            // Day by day from the due date: a named weekday counts when its
            // week is `interval` weeks on from the due date's week.
            let dueWeek = calendar.dateInterval(of: .weekOfYear, for: due)?.start ?? due
            var day = due
            while day <= limit, steps < 2000 {
                steps += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                let weekday = calendar.component(.weekday, from: day)
                guard rule.weekdays.contains(weekday) else { continue }
                let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
                let weeks = calendar.dateComponents([.weekOfYear], from: dueWeek, to: week).weekOfYear ?? 0
                if weeks % rule.interval == 0 { consider(day) }
            }
        default:
            let (component, unit): (Calendar.Component, Int) = {
                switch rule.frequency {
                case .daily:   return (.day, rule.interval)
                case .weekly:  return (.day, 7 * rule.interval)
                case .monthly: return (.month, rule.interval)
                case .yearly:  return (.year, rule.interval)
                }
            }()
            var date = due
            var n = 0
            while date <= limit, steps < 2000 {
                steps += 1
                n += 1
                guard let next = calendar.date(byAdding: component, value: unit * n, to: due) else { break }
                date = next
                consider(date)
            }
        }
        return found
    }
}

import Foundation

/// One calendar or reminder list as the Settings window lists it
/// (2026-09-30): grouped by account, with its colour and a switch.
public struct CalendarInfo: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case event, reminder
    }

    public struct RGB: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public let id: String
    public let title: String
    public let source: String
    public let kind: Kind
    public let color: RGB?

    public init(id: String, title: String, source: String, kind: Kind, color: RGB?) {
        self.id = id
        self.title = title
        self.source = source
        self.kind = kind
        self.color = color
    }

    /// Accounts in alphabetical order, calendars alphabetical within.
    public static func grouped(_ calendars: [CalendarInfo]) -> [(source: String, calendars: [CalendarInfo])] {
        let bySource = Dictionary(grouping: calendars, by: \.source)
        return bySource.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { source in
            (source, bySource[source]!.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
    }
}

import Foundation

/// A calendar event or timed reminder: a row or an all-day chip in the
/// calendar card, and the Settings previews' meeting and reminder blips
/// (2026-10-26; it began as the hover preview, retired then). `AppModel`
/// builds these from `CalendarService`.
public struct UpcomingEvent: Sendable, Equatable {
    public struct Tint: Sendable, Equatable {
        public let red: Double, green: Double, blue: Double
        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// An event draws a bar in its calendar's colour in the card; a
    /// reminder draws Reminders' ring in its list's, in the ear too
    /// (2026-10-21).
    public enum Kind: Sendable, Equatable {
        case event, reminder
    }

    public let title: String
    public let kind: Kind
    /// The calendar's or list's colour; `nil` draws a neutral grey.
    public let tint: Tint?
    /// A blip's leading ear: "calendar" for an event, "circle" for a
    /// reminder; an all-day chip's glyph: "star.circle.fill" and the like.
    public let symbolName: String
    /// A blip's trailing ear: "42m", "2h 10m", "Now".
    public let compactText: String
    /// A blip's caption line: "Title · 14:00".
    public let caption: String
    /// A card row's time: the start, "14:00", or "Now" for an event under
    /// way.
    public let time: String
    /// A reminder whose time has passed: its time is drawn red, as
    /// Reminders draws it.
    public let isPastDue: Bool
    /// What a click opens: the join link, or the app model's open-Calendar
    /// stand-in.
    public let url: URL?

    public init(title: String, symbolName: String = "calendar", compactText: String, caption: String, time: String = "", url: URL?, tint: Tint? = nil, kind: Kind = .event, isPastDue: Bool = false) {
        self.title = title
        self.kind = kind
        self.tint = tint
        self.symbolName = symbolName
        self.compactText = compactText
        self.caption = caption
        self.time = time
        self.isPastDue = isPastDue
        self.url = url
    }
}

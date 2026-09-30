import Foundation

/// The next calendar event, for the hover preview (2026-09-29): with
/// nothing playing and no blip live, resting the cursor on the island
/// shows it in the meeting blip's own layout — calendar glyph and
/// countdown in the ears, "Title · 14:00" under the hole — and a click
/// joins. `AppModel` keeps it fresh from `CalendarService`.
public struct UpcomingEvent: Sendable, Equatable {
    public let title: String
    /// Leading ear: "calendar" for an event, "checklist" for a reminder.
    public let symbolName: String
    /// Trailing ear: "42m", "2h 10m", "Now".
    public let compactText: String
    /// The caption line: "Title · 14:00".
    public let caption: String
    /// The time alone, for a list row: "14:00–14:30", "Tomorrow at 06:15".
    public let when: String
    /// What a click opens: the join link, or the app model's open-Calendar
    /// stand-in.
    public let url: URL?

    public init(title: String, symbolName: String = "calendar", compactText: String, caption: String, when: String = "", url: URL?) {
        self.title = title
        self.symbolName = symbolName
        self.compactText = compactText
        self.caption = caption
        self.when = when
        self.url = url
    }
}

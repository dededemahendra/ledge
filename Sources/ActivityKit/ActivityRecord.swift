import CoreGraphics
import Foundation

/// A colour meaning for a glyph — the island is white-on-black everywhere
/// except where colour carries information the system's own indicators
/// use it for: green while charging, red when low.
public enum ActivityTint: Sendable, Equatable {
    case positive
    case warning
    /// One of Apple's system colours by its name ("systemIndigoColor",
    /// "indigo"): a Focus's own tint (2026-09-30).
    case system(String)
    /// The item's own colour, the way its app draws it: a reminder's list
    /// (2026-10-21).
    case color(red: Double, green: Double, blue: Double)
}

/// One reading among several in a blip's trailing ear — a bud's or a
/// case's charge (2026-09-30) — with its glyph where there is one.
public struct ActivityPart: Sendable, Equatable {
    public let symbolName: String?
    public let text: String

    public init(symbolName: String?, text: String) {
        self.symbolName = symbolName
        self.text = text
    }
}

/// A scoreline an iPhone Live Activity is running (2026-10-01): two
/// sides with a crest and a figure, and whatever the card says between
/// them — the period and a running clock.
public struct ActivityScore: Sendable, Equatable {
    public struct Side: Sendable, Equatable {
        public let name: String
        public let value: String
        /// The crest as a round picture, cut from the card.
        public let crest: Data?

        public init(name: String, value: String, crest: Data?) {
            self.name = name
            self.value = value
            self.crest = crest
        }
    }

    public let home: Side
    public let away: Side
    public let status: String?
    public let clock: String?
    public let title: String?

    public init(home: Side, away: Side, status: String? = nil, clock: String? = nil, title: String? = nil) {
        self.home = home
        self.away = away
        self.status = status
        self.clock = clock
        self.title = title
    }
}

/// One thing the island is currently saying.
public struct ActivityRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ActivityKind
    public let insertedAt: Date
    /// `nil` means sticky.
    public let ttl: TimeInterval?
    public let title: String
    public let detail: String?
    /// Very short glanceable form (e.g. "87%") for layouts with no room for
    /// `title` — see `NotchController.ActivityDisplay.compactText`.
    public let compactText: String?
    /// SF Symbol shown in the leading ear — see `NotchController.ActivityDisplay.symbolName`.
    public let symbolName: String?
    /// `0...1` progress bar, or `nil` for activities without one — see
    /// `NotchController.ActivityDisplay.barFill`.
    public let barFill: Double?
    /// Encoded image for the leading ear (a product render for a device
    /// activity); wins over `symbolName` when present — see
    /// `NotchController.ActivityDisplay.artwork`.
    public let artwork: Data?
    /// Colour for `symbolName`, when the state warrants one — see
    /// `ActivityTint`. `nil` is the island's white.
    public let tint: ActivityTint?
    /// What a click on the blip opens while it shows (a meeting's join
    /// link), or `nil` — then the blip is just a blip.
    public let url: URL?
    /// Several readings side by side in the trailing ear, instead of
    /// `compactText`; the island widens to fit them.
    public let parts: [ActivityPart]?
    /// A scoreline, when the activity is a match — see `ActivityScore`.
    public let score: ActivityScore?
    /// What an activity that is not a match says, line by line — shown
    /// in the open panel.
    public let lines: [String]

    public init(
        id: String,
        kind: ActivityKind,
        insertedAt: Date,
        ttl: TimeInterval?,
        title: String,
        detail: String? = nil,
        compactText: String? = nil,
        symbolName: String? = nil,
        barFill: Double? = nil,
        artwork: Data? = nil,
        tint: ActivityTint? = nil,
        url: URL? = nil,
        parts: [ActivityPart]? = nil,
        score: ActivityScore? = nil,
        lines: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.insertedAt = insertedAt
        self.ttl = ttl
        self.title = title
        self.detail = detail
        self.compactText = compactText
        self.symbolName = symbolName
        self.barFill = barFill.map { min(1, max(0, $0)) }
        self.artwork = artwork
        self.tint = tint
        self.url = url
        self.parts = parts
        self.score = score
        self.lines = lines
    }

    public var isSticky: Bool { ttl == nil }

    public func hasExpired(at now: Date) -> Bool {
        guard let ttl else { return false }
        return now.timeIntervalSince(insertedAt) >= ttl
    }
}

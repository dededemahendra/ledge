import Foundation

/// A colour meaning for a glyph — the island is white-on-black everywhere
/// except where colour carries information the system's own indicators
/// use it for: green while charging, red when low.
public enum ActivityTint: Sendable, Equatable {
    case positive
    case warning
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
        url: URL? = nil
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
    }

    public var isSticky: Bool { ttl == nil }

    public func hasExpired(at now: Date) -> Bool {
        guard let ttl else { return false }
        return now.timeIntervalSince(insertedAt) >= ttl
    }
}

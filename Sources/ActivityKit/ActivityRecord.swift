import Foundation

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

    public init(
        id: String,
        kind: ActivityKind,
        insertedAt: Date,
        ttl: TimeInterval?,
        title: String,
        detail: String? = nil,
        compactText: String? = nil,
        symbolName: String? = nil,
        barFill: Double? = nil
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
    }

    public var isSticky: Bool { ttl == nil }

    public func hasExpired(at now: Date) -> Bool {
        guard let ttl else { return false }
        return now.timeIntervalSince(insertedAt) >= ttl
    }
}

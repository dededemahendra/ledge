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

    public init(
        id: String,
        kind: ActivityKind,
        insertedAt: Date,
        ttl: TimeInterval?,
        title: String,
        detail: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.insertedAt = insertedAt
        self.ttl = ttl
        self.title = title
        self.detail = detail
    }

    public var isSticky: Bool { ttl == nil }

    public func hasExpired(at now: Date) -> Bool {
        guard let ttl else { return false }
        return now.timeIntervalSince(insertedAt) >= ttl
    }
}

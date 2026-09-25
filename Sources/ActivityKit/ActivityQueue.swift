import Foundation

/// Holds what the island is showing. Pure value type: no timers, no clock of
/// its own. Whoever owns it calls `prune(at:hovered:)`.
public struct ActivityQueue: Sendable, Equatable {
    /// Compact slots available — matches the chosen layout (spec §6).
    public static let visibleSlots = 2

    /// One record per kind: inserting the same kind replaces it.
    private var records: [ActivityKind: ActivityRecord] = [:]

    public init() {}

    public var count: Int { records.count }
    public var isEmpty: Bool { records.isEmpty }

    /// Highest priority first. Stable, because at most one record exists per kind.
    public var ordered: [ActivityRecord] {
        records.values.sorted { $0.kind.priority > $1.kind.priority }
    }

    public var visible: [ActivityRecord] {
        Array(ordered.prefix(Self.visibleSlots))
    }

    public var overflowCount: Int {
        max(0, count - Self.visibleSlots)
    }

    /// Coalesces by kind, restarting that kind's TTL window.
    public mutating func insert(_ record: ActivityRecord) {
        records[record.kind] = record
    }

    public mutating func remove(kind: ActivityKind) {
        records[kind] = nil
    }

    /// Drops everything whose TTL has elapsed.
    ///
    /// While hovered, nothing is dropped — but nothing is renewed either, so
    /// releasing the cursor expires everything already due in a single pass.
    public mutating func prune(at now: Date, hovered: Bool) {
        guard !hovered else { return }
        records = records.filter { !$0.value.hasExpired(at: now) }
    }
}

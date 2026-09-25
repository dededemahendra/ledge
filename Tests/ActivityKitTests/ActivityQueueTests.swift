import Testing
import Foundation
@testable import ActivityKit

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func record(
    _ kind: ActivityKind,
    id: String? = nil,
    at: Date = t0,
    ttl: TimeInterval? = nil,
    title: String = "x"
) -> ActivityRecord {
    ActivityRecord(
        id: id ?? kind.rawValue,
        kind: kind,
        insertedAt: at,
        ttl: ttl ?? kind.defaultTTL,
        title: title,
        detail: nil
    )
}

@Test func prioritiesAndTTLsMatchTheSpec() {
    #expect(ActivityKind.hud.priority == 100)
    #expect(ActivityKind.power.priority == 60)
    #expect(ActivityKind.device.priority == 50)
    #expect(ActivityKind.notification.priority == 40)
    #expect(ActivityKind.media.priority == 10)

    #expect(ActivityKind.hud.defaultTTL == 1.5)
    #expect(ActivityKind.power.defaultTTL == 3)
    #expect(ActivityKind.device.defaultTTL == 3)
    #expect(ActivityKind.notification.defaultTTL == 5)
    #expect(ActivityKind.media.defaultTTL == nil, "media is sticky")
}

@Test func emptyQueueShowsNothing() {
    let q = ActivityQueue()
    #expect(q.isEmpty)
    #expect(q.visible.isEmpty)
    #expect(q.overflowCount == 0)
}

@Test func insertionOrdersByPriorityNotArrival() {
    var q = ActivityQueue()
    q.insert(record(.media))
    q.insert(record(.hud))
    #expect(q.visible.map(\.kind) == [.hud, .media])
}

@Test func sameKindCoalescesInsteadOfStacking() {
    var q = ActivityQueue()
    q.insert(record(.hud, title: "volume 40"))
    q.insert(record(.hud, title: "volume 45"))
    q.insert(record(.hud, title: "volume 50"))
    #expect(q.count == 1, "spinning the volume wheel must not queue twenty activities")
    #expect(q.visible.first?.title == "volume 50")
}

@Test func coalescingResetsTheTTLClock() {
    var q = ActivityQueue()
    q.insert(record(.hud, at: t0))
    q.insert(record(.hud, at: t0.addingTimeInterval(1.4)))
    q.prune(at: t0.addingTimeInterval(2.0), hovered: false)
    #expect(q.count == 1, "the second insert restarted the 1.5s window")
    q.prune(at: t0.addingTimeInterval(3.0), hovered: false)
    #expect(q.isEmpty)
}

@Test func onlyTwoSlotsAreVisibleAndTheRestOverflow() {
    var q = ActivityQueue()
    q.insert(record(.hud))
    q.insert(record(.power))
    q.insert(record(.device))
    q.insert(record(.notification))
    #expect(q.count == 4)
    #expect(q.visible.map(\.kind) == [.hud, .power])
    #expect(q.overflowCount == 2)
}

@Test func expiredActivitiesArePruned() {
    var q = ActivityQueue()
    q.insert(record(.power, at: t0))
    q.prune(at: t0.addingTimeInterval(2.9), hovered: false)
    #expect(q.count == 1)
    q.prune(at: t0.addingTimeInterval(3.1), hovered: false)
    #expect(q.isEmpty)
}

@Test func stickyMediaNeverExpires() {
    var q = ActivityQueue()
    q.insert(record(.media, at: t0))
    q.prune(at: t0.addingTimeInterval(86_400), hovered: false)
    #expect(q.count == 1)
}

// Review Focus 5.
@Test func hoverSuppressesExpiryAndUnhoverThenExpiresEverythingDue() {
    var q = ActivityQueue()
    q.insert(record(.power, at: t0))
    q.insert(record(.device, at: t0))
    #expect(q.count == 2)

    let wellPastBoth = t0.addingTimeInterval(10)
    q.prune(at: wellPastBoth, hovered: true)
    #expect(q.count == 2, "never yank the island out from under the cursor")

    q.prune(at: wellPastBoth, hovered: false)
    #expect(q.isEmpty, "both must go, in one pass, with no lost update")
}

@Test func hoverDoesNotExtendTheDeadlineAfterRelease() {
    // Hovering pauses expiry; it must not silently renew the TTL.
    var q = ActivityQueue()
    q.insert(record(.hud, at: t0))
    q.prune(at: t0.addingTimeInterval(1.0), hovered: true)
    q.prune(at: t0.addingTimeInterval(1.6), hovered: false)
    #expect(q.isEmpty)
}

@Test func removingAKindByHand() {
    var q = ActivityQueue()
    q.insert(record(.media))
    q.insert(record(.power))
    q.remove(kind: .media)
    #expect(q.visible.map(\.kind) == [.power])
}

@Test func equalPrioritiesBreakTiesDeterministically() {
    var q = ActivityQueue()
    q.insert(record(.device, id: "b", at: t0.addingTimeInterval(1)))
    q.insert(record(.notification, id: "a", at: t0))
    // device (50) outranks notification (40) regardless of arrival order
    #expect(q.visible.map(\.id) == ["b", "a"])
}

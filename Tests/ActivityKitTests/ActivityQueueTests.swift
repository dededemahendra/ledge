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
    #expect(ActivityKind.liveActivity.priority == 15, "above music, below a Clock timer")

    #expect(ActivityKind.hud.defaultTTL == 1.5)
    #expect(ActivityKind.power.defaultTTL == 3)
    #expect(ActivityKind.device.defaultTTL == 3)
    #expect(ActivityKind.notification.defaultTTL == 5)
    #expect(ActivityKind.media.defaultTTL == nil, "media is sticky")
    #expect(ActivityKind.liveActivity.defaultTTL == nil, "a live activity stays while its pill does")
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

@Test func higherPriorityWinsRegardlessOfArrivalOrderOrId() {
    var q = ActivityQueue()
    q.insert(record(.device, id: "b", at: t0.addingTimeInterval(1)))
    q.insert(record(.notification, id: "a", at: t0))
    // device (50) outranks notification (40) whatever the arrival order or id.
    #expect(q.visible.map(\.id) == ["b", "a"])
}

/// `visible`'s determinism depends on this: `records` is a Dictionary with
/// per-process randomised iteration order, so if two kinds ever shared a
/// priority the two-slot prefix could vary between runs.
@Test func everyKindHasADistinctPriority() {
    let priorities = ActivityKind.allCases.map(\.priority)
    #expect(Set(priorities).count == priorities.count)
}

@Test func kindsCompareByPriority() {
    #expect(ActivityKind.media < ActivityKind.hud)
    #expect(ActivityKind.hud > ActivityKind.power)
}

/// An update (2026-10-22): below every other blip, above a Clock timer,
/// eight seconds to read like a meeting.
@Test func anUpdateIsTheQuietestBlip() {
    #expect(ActivityKind.update.priority == 35)
    #expect(ActivityKind.update.defaultTTL == 8)
    #expect(ActivityKind.update < .notification && ActivityKind.update > .timer)
}

@Test func gitHubBlipsAndTheRunningItemSitWhereTheSpecSays() {
    #expect(ActivityKind.github.priority == 38)
    #expect(ActivityKind.github.defaultTTL == 8)
    #expect(ActivityKind.github < .notification && ActivityKind.github > .update)
    #expect(ActivityKind.githubRun.priority == 18)
    #expect(ActivityKind.githubRun.defaultTTL == nil, "sticky while anything runs")
    #expect(ActivityKind.githubRun < .timer && ActivityKind.githubRun > .liveActivity)
}

@Test func aRecordCarriesItsBadge() {
    let record = ActivityRecord(id: "github-run", kind: .githubRun, insertedAt: Date(), ttl: nil, title: "Checks running", badge: 2)
    #expect(record.badge == 2)
}

@Test func aRecordCarriesItsSegments() {
    let record = ActivityRecord(id: "github-run", kind: .githubRun, insertedAt: Date(), ttl: nil, title: "Checks running",
                                segments: [.passed, .running])
    #expect(record.segments == [.passed, .running])
}

import Testing
import Foundation
@testable import NotchKit

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

@Test func aPassThroughShorterThanTheDwellNeverHovers() {
    var hover = HoverIntentTracker(dwell: 0.2)
    #expect(hover.pointer(inside: true, at: t0) == .none)
    #expect(hover.isPointerInside, "the geometric fact is immediate — clicks need it")
    #expect(!hover.isHovering)
    #expect(hover.pointer(inside: true, at: t0 + 0.1) == .none)
    #expect(hover.pointer(inside: false, at: t0 + 0.15) == .none, "nothing was promoted, so nothing to undo")
    #expect(!hover.isPointerInside)
    #expect(hover.pendingUntil == nil)
}

@Test func dwellingPromotesOnceAndLeavingUnhoversAtOnce() {
    var hover = HoverIntentTracker(dwell: 0.2)
    _ = hover.pointer(inside: true, at: t0)
    #expect(hover.pendingUntil == t0 + 0.2)
    #expect(hover.pointer(inside: true, at: t0 + 0.2) == .hovered)
    #expect(hover.isHovering)
    #expect(hover.pendingUntil == nil)
    #expect(hover.pointer(inside: true, at: t0 + 1) == .none, "already hovering: nothing to announce")
    #expect(hover.pointer(inside: false, at: t0 + 1.01) == .unhovered, "leaving needs no dwell")
    #expect(!hover.isHovering)
}

@Test func reEntryRestartsTheDwell() {
    var hover = HoverIntentTracker(dwell: 0.2)
    _ = hover.pointer(inside: true, at: t0)
    _ = hover.pointer(inside: false, at: t0 + 0.15)
    _ = hover.pointer(inside: true, at: t0 + 0.16)
    #expect(hover.pointer(inside: true, at: t0 + 0.3) == .none, "0.14 s since re-entry: not yet")
    #expect(hover.pointer(inside: true, at: t0 + 0.36) == .hovered)
}

@Test func aZeroDwellHoversOnEntry() {
    var hover = HoverIntentTracker(dwell: 0)
    #expect(hover.pointer(inside: true, at: t0) == .hovered)
}

@Test func resetForgetsEverything() {
    var hover = HoverIntentTracker(dwell: 0.2)
    _ = hover.pointer(inside: true, at: t0)
    _ = hover.pointer(inside: true, at: t0 + 0.2)
    hover.reset()
    #expect(!hover.isHovering && !hover.isPointerInside && hover.pendingUntil == nil)
    #expect(hover.pointer(inside: true, at: t0 + 1) == .none, "a fresh dwell starts")
}

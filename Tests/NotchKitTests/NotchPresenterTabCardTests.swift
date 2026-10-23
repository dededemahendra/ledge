import Testing
import CoreGraphics
import Foundation
import SwiftUI
@testable import NotchKit

// The tab's card holds from anywhere on the tab (2026-10-23). The card is
// 356 pt wide and centred, so beside a wide island it does not cover where
// the tab stood; opened from there it closed on the presenter's next check
// and reopened every other tick. The tab's footprint now holds it.

private let canvas = NotchPresenter.canvas

private func notch(_ width: CGFloat) -> NotchMetrics {
    NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: width, height: 32))
}

/// A point on the tab's body beside `island`, `dx` in from its left side.
private func onTheTab(beside island: NotchShapeParameters, dx: CGFloat, y: CGFloat = 16) -> CGPoint {
    CGPoint(x: canvas.midX + island.width / 2 + NotchMetrics.tabGap + dx, y: y)
}

@Test func theTabsFootprintHoldsItsCardUntilThePointerLeavesBoth() {
    let m = notch(179)
    let island = m.oneActivity(earWidth: NotchMetrics.activityEarMaximum)
    let footprint = NotchPresenter.tabZone(beside: island, tab: m.tab)
    let card = NotchPresenter.hoverParameters(state: .expanded, drawn: m.expanded, metrics: m)
    let point = onTheTab(beside: island, dx: 35)
    // The card alone does not reach the tab's outer part.
    #expect(NotchPresenter.hoverPart(at: point, island: card, tab: nil) == nil)

    let held = NotchPresenter.hoverReading(at: point, island: card, tab: nil, footprint: footprint, expanded: true)
    #expect(held.part == .island)
    #expect(held.footprint == footprint)
    #expect(IslandRegionShape(island: card, tab: nil, footprint: held.footprint).path(in: canvas).contains(point))

    let inCard = NotchPresenter.hoverReading(
        at: CGPoint(x: canvas.midX, y: 80), island: card, tab: nil, footprint: footprint, expanded: true
    )
    #expect(inCard.part == .island && inCard.footprint == footprint)

    let away = NotchPresenter.hoverReading(
        at: CGPoint(x: canvas.midX, y: 300), island: card, tab: nil, footprint: footprint, expanded: true
    )
    #expect(away.part == nil && away.footprint == nil)

    // The card closed: the footprint no longer counts.
    let closed = NotchPresenter.hoverReading(at: point, island: island, tab: nil, footprint: footprint, expanded: false)
    #expect(closed.part == nil && closed.footprint == nil)
}

/// The reviewer's replay: the presenter's own pass, run as `updateHover`
/// runs it and again as `syncWindowToVisibility` re-checks in the same
/// turn, every quarter second, from every point across the tab, for leads
/// whose ears span 38…130 pt on the 179 pt notch and on "More Space"'s 208.
@MainActor
@Test func theTabsCardHoldsFromAnywhereOnTheTab() {
    let leads = ["4:12", "12:34", "1:02:34"] + (5...24).map { String(repeating: "0", count: $0) }
    for notchWidth in [179.0, 208.0] {
        let m = notch(notchWidth)
        var ears: Set<CGFloat> = []
        for lead in leads {
            let p = NotchPresenter(space: nil)
            let c = p.controller
            c.metrics = m
            c.setAgentPanel(AgentPanelData(hero: nil, rows: [
                .init(id: "s1", name: "ledge", mark: .idle, url: URL(string: "ledge://agent/s1")!),
            ]))
            c.setActivities([.init(id: NotchController.callActivityID, title: "On a call", compactText: lead)], overflow: 0,
                            tab: .init(id: NotchController.agentRunActivityID, title: "2 working", compactText: "2"))
            #expect(c.state == .activity && c.isTabShowing)
            let island = c.parameters
            ears.insert(m.earWidth(forIslandWidth: island.width))
            var now = Date(timeIntervalSince1970: 1_000_000)
            for dx in stride(from: 1.0, through: NotchMetrics.tabWidth - 1, by: 2.0) {
                for y in [4.0, 16.0, 28.0] {
                    let point = onTheTab(beside: island, dx: dx, y: y)
                    // Only points on the tab: its bottom corners are round.
                    guard NotchPresenter.hoverPart(at: point, island: island, tab: c.tabParameters) == .tab else { continue }
                    let label = "notch \(notchWidth), lead \(lead), dx \(dx), y \(y)"
                    // Arrive, then dwell.
                    p.reevaluateHover(at: point, now: now)
                    now += 0.25
                    for tick in 0..<3 {
                        p.reevaluateHover(at: point, now: now)   // the move or the tick
                        if tick == 0 { #expect(c.panel == .agents, "\(label)") }
                        p.reevaluateHover(at: point, now: now)   // the same-pass re-check
                        #expect(c.state == .expanded, "\(label), tick \(tick)")
                        #expect(c.isHovered && p.acceptsMouse, "\(label), tick \(tick)")
                        #expect(p.claimedRegion.path(in: canvas).contains(point), "\(label), tick \(tick)")
                        now += 0.25
                    }
                    // Leaving card and footprint both lets it go.
                    p.reevaluateHover(at: CGPoint(x: canvas.midX, y: canvas.maxY - 1), now: now)
                    #expect(!c.isHovered && c.state == .activity && p.tabFootprint == nil, "\(label)")
                    now += 0.25
                }
            }
        }
        #expect(ears.min() == NotchMetrics.activityEarWidth && ears.max() == NotchMetrics.activityEarMaximum)
    }
}

import Testing
import CoreGraphics
import SwiftUI
@testable import NotchKit

private let notch = NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 179, height: 32))

private func tabFrame(_ island: NotchShapeParameters, _ tab: NotchTabParameters) -> CGRect {
    NotchTabShape(island: island, tab: tab).path(in: NotchPresenter.canvas).boundingRect
}

@Test func aPointOnTheIslandIsTheIsland() {
    let island = notch.oneActivity
    let tab = notch.tab(beside: island)
    let point = CGPoint(x: NotchPresenter.canvas.midX, y: 10)
    #expect(NotchPresenter.hoverPart(at: point, island: island, tab: tab, metrics: notch) == .island)
}

@Test func aPointOnTheTabIsTheTab() {
    let island = notch.oneActivity
    let tab = notch.tab(beside: island)
    let frame = tabFrame(island, tab)
    let point = CGPoint(x: frame.midX, y: 10)
    #expect(NotchPresenter.hoverPart(at: point, island: island, tab: tab, metrics: notch) == .tab)
}

@Test func pointsInTheGapAndBesideTheTabPassThrough() {
    let island = notch.oneActivity
    let tab = notch.tab(beside: island)
    let frame = tabFrame(island, tab)
    let gap = CGPoint(x: NotchPresenter.canvas.midX + island.width / 2 + 3, y: 10)
    let right = CGPoint(x: frame.maxX + 4, y: 10)
    let below = CGPoint(x: frame.midX, y: frame.maxY + 4)
    #expect(NotchPresenter.hoverPart(at: gap, island: island, tab: tab, metrics: notch) == nil)
    #expect(NotchPresenter.hoverPart(at: right, island: island, tab: tab, metrics: notch) == nil)
    #expect(NotchPresenter.hoverPart(at: below, island: island, tab: tab, metrics: notch) == nil)
}

@Test func withNoTabOnlyTheIslandCounts() {
    let island = notch.oneActivity
    let frame = tabFrame(island, notch.tab(beside: island))
    let point = CGPoint(x: frame.midX, y: 10)
    #expect(NotchPresenter.hoverPart(at: point, island: island, tab: nil, metrics: notch) == nil)
}

@Test func aPillsTabReachesUpOverItsInsetToTheTopEdge() {
    let pill = NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 44, height: 28), isVirtual: true)
    let island = pill.oneActivity
    let tab = pill.tab(beside: island)
    let frame = tabFrame(island, tab)
    let point = CGPoint(x: frame.midX, y: 1)
    #expect(NotchPresenter.hoverPart(at: point, island: island, tab: tab, metrics: pill) == .tab)
}

import Testing
import CoreGraphics
import SwiftUI
@testable import NotchKit

private let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
private let notch = NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 179, height: 32))

/// A round bubble beside the island, as the iPhone's second island is
/// (2026-10-23, user's call): as tall as the notch, 6 pt to its right, its
/// top against the screen's edge like the island's.
@Test func onANotchTheTabIsACircleBesideTheIsland() {
    let island = notch.oneActivity
    let tab = notch.tab
    #expect(tab.gap == 6)
    #expect(tab.width == 32)
    #expect(tab.height == 32)
    #expect(tab.bottomRadius == 16)
    #expect(tab.topRadius == 16)
    #expect(tab.outerFillet == 0)
    #expect(tab.topInset == 0)

    let bounds = NotchTabShape(island: island, tab: tab).path(in: canvas).boundingRect
    let left = canvas.midX + island.width / 2 + 6
    #expect(abs(bounds.minX - left) < 0.001)
    #expect(abs(bounds.width - 32) < 0.001)
    #expect(abs(bounds.minY) < 0.001)
    #expect(abs(bounds.height - 32) < 0.001)
}

@Test func onAPillTheTabIsACircleBesideThePill() {
    let pill = NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 44, height: 28), isVirtual: true)
    let island = pill.oneActivity
    let tab = pill.tab
    #expect(tab.width == island.height)
    #expect(tab.height == island.height)
    #expect(tab.topInset == NotchMetrics.pillTopInset)
    #expect(tab.topRadius == island.height / 2)
    #expect(tab.bottomRadius == island.height / 2)
    #expect(tab.outerFillet == 0)
    #expect(tab.gap == 6)

    let bounds = NotchTabShape(island: island, tab: tab).path(in: canvas).boundingRect
    #expect(abs(bounds.minX - (canvas.midX + island.width / 2 + 6)) < 0.001)
    #expect(abs(bounds.width - island.height) < 0.001)
    #expect(abs(bounds.height - island.height) < 0.001)
    #expect(abs(bounds.minY - NotchMetrics.pillTopInset) < 0.001)
}

@Test func theTabFollowsAWiderIsland() {
    let narrow = notch.oneActivity
    let wide = notch.captioned(fitting: 400)
    let tab = notch.tab
    let before = NotchTabShape(island: narrow, tab: notch.tab).path(in: canvas).boundingRect
    let after = NotchTabShape(island: wide, tab: tab).path(in: canvas).boundingRect
    #expect(abs((after.minX - before.minX) - (400 - narrow.width) / 2) < 0.001)
    // The body never starts before the island's right edge plus the gap.
    #expect(after.minX + tab.outerFillet >= canvas.midX + wide.width / 2 + 6 - 0.001)
}

@Test func aTuckedTabHasNoWidthAtTheIslandsEdge() {
    let island = notch.oneActivity
    let tucked = notch.tabTucked
    #expect(tucked.gap == 0)
    #expect(tucked.width == 0)
    #expect(tucked.height == notch.tab.height)
    #expect(NotchTabShape(island: island, tab: tucked).path(in: canvas).isEmpty)
}

@Test func aCaptionedIslandDoesNotStretchTheTab() {
    let island = notch.captioned(fitting: 400)
    let bounds = NotchTabShape(island: island, tab: notch.tab).path(in: canvas).boundingRect
    #expect(abs(bounds.height - 32) < 0.001)

    let pill = NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 44, height: 28), isVirtual: true)
    let big = pill.captioned(fitting: 400)
    let tab = pill.tab
    #expect(tab.height == pill.oneActivity.height)
    let pb = NotchTabShape(island: big, tab: tab).path(in: canvas).boundingRect
    #expect(abs(pb.height - pill.oneActivity.height) < 0.001)
    #expect(abs(pb.minX - (canvas.midX + big.width / 2 + 6)) < 0.001)
}

/// Budding out, the round tab stays within its width: no flares beside it.
@Test func aBuddingTabHasNoFlares() {
    let island = notch.oneActivity
    var tab = notch.tab
    tab.width = 20
    let bounds = NotchTabShape(island: island, tab: tab).path(in: canvas).boundingRect
    #expect(abs(bounds.width - 20) < 0.001)
}

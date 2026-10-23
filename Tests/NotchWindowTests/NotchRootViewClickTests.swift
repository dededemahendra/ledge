import Testing
import AppKit
import SwiftUI
@testable import NotchKit

// Clicks on the real `NotchRootView` in an offscreen window (2026-10-23):
// the island's tap once sat on the canvas while its press drag sat on the
// island itself, and the child's drag won, so a click on the island did
// nothing. Only a real event through a real hosting view shows that.

@MainActor
private final class Taps {
    var island = 0
    var tab = 0
}

@MainActor
private func hostedIsland(_ controller: NotchController, _ taps: Taps) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
        contentRect: NSRect(origin: NSPoint(x: -5000, y: -5000), size: NotchMetrics.canvasSize),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: NotchRootView(
        controller: controller,
        onTap: { taps.island += 1 },
        onTabTap: { taps.tab += 1 }
    ))
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    return window
}

/// A press and release at `point`, in the canvas's top-left, y-down space.
@MainActor
private func click(_ window: NSWindow, at point: CGPoint) {
    let location = NSPoint(x: point.x, y: NotchMetrics.canvasSize.height - point.y)
    let start = ProcessInfo.processInfo.systemUptime
    for (type, delay) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.05)] {
        guard let event = NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [], timestamp: start + delay,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        ) else { continue }
        window.sendEvent(event)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
}

@MainActor
private func islandWithATab() -> NotchController {
    let c = NotchController(metrics: NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 179, height: 32)))
    c.setActivities([.init(id: NotchController.callActivityID, title: "On a call", compactText: "4:12")], overflow: 0,
                    tab: .init(id: NotchController.agentRunActivityID, title: "2 working", compactText: "1:05"))
    return c
}

@MainActor
@Test func aClickOnTheIslandTapsTheIslandOnce() {
    let c = islandWithATab()
    #expect(c.state == .activity && c.isTabShowing)
    let taps = Taps()
    let window = hostedIsland(c, taps)
    defer { window.orderOut(nil) }
    click(window, at: CGPoint(x: NotchPresenter.canvas.midX - c.parameters.width / 2 + 19, y: 16))
    #expect(taps.island == 1)
    #expect(taps.tab == 0)
}

@MainActor
@Test func aClickOnTheTabTapsTheTabAndNeverTheIsland() {
    let c = islandWithATab()
    let taps = Taps()
    let window = hostedIsland(c, taps)
    defer { window.orderOut(nil) }
    click(window, at: CGPoint(x: NotchPresenter.canvas.midX + c.parameters.width / 2 + NotchMetrics.tabGap + 20, y: 16))
    #expect(taps.island == 0)
    #expect(taps.tab == 1)
}

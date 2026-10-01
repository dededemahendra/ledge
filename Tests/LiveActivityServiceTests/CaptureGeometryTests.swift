import Testing
import Foundation
@testable import LiveActivityService

@Test func theSourceRectIsRelativeToTheDisplay() {
    let pill = CGRect(x: 973, y: 4, width: 46, height: 24)
    #expect(CaptureGeometry.sourceRect(for: pill, inDisplay: CGRect(x: 0, y: 0, width: 1470, height: 956)) == pill)
    #expect(CaptureGeometry.sourceRect(for: pill, inDisplay: CGRect(x: -1470, y: -100, width: 1470, height: 956))
            == CGRect(x: 2443, y: 104, width: 46, height: 24), "a display left of and above the primary")
}

@Test func pixelSizeFollowsTheScaleAndNeverCollapses() {
    let pill = CGRect(x: 973, y: 4, width: 46, height: 24)
    #expect(CaptureGeometry.pixelSize(for: pill, scale: 2) == (92, 48))
    #expect(CaptureGeometry.pixelSize(for: pill, scale: 1) == (46, 24))
    #expect(CaptureGeometry.pixelSize(for: CGRect(x: 0, y: 0, width: 0.2, height: 0.2), scale: 2) == (1, 1))
}

@MainActor
@Test func thePillIsKnownByItsIdentifierPrefix() {
    #expect(PillLocator.isPill(identifier: "live-activity-pill-com.apple.chrono.WidgetRenderer-Activities"))
    #expect(!PillLocator.isPill(identifier: "com.apple.menuextra.battery"))
    #expect(!PillLocator.isPill(identifier: nil))
}

@Test func locationsCompareByPlaceNotHandle() {
    let a = PillLocation(identifier: "live-activity-pill-x", frame: CGRect(x: 973, y: 4, width: 46, height: 24))
    let b = PillLocation(identifier: "live-activity-pill-x", frame: CGRect(x: 973, y: 4, width: 46, height: 24))
    let moved = PillLocation(identifier: "live-activity-pill-x", frame: CGRect(x: 950, y: 4, width: 46, height: 24))
    #expect(a == b)
    #expect(a != moved, "a moved pill restarts the capture over the new rectangle")
}

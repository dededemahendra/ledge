import Testing
import CoreGraphics
@testable import NotchKit

/// Claude's mark (2026-10-26): the asset's path, read whole into a unit
/// square — its rays reach from 6.2 to 241.8 of the asset's 248 on both
/// axes, centred — and scaled into the middle of whatever it is given.
@Test func claudesMarkFillsItsSquareAsTheAssetDoes() {
    let bounds = ClaudeMark.unit.boundingRect
    #expect(abs(bounds.minX - 6.2 / 248) < 0.002 && abs(bounds.maxX - 241.8 / 248) < 0.002, "\(bounds)")
    #expect(abs(bounds.minY - 6.2 / 248) < 0.002 && abs(bounds.maxY - 241.8 / 248) < 0.002, "\(bounds)")
    #expect(ClaudeMark.unit.contains(CGPoint(x: 0.5, y: 0.5)), "the hub is filled")
    #expect(!ClaudeMark.unit.contains(CGPoint(x: 0.1, y: 0.1)), "between the rays is not")

    let drawn = ClaudeMark().path(in: CGRect(x: 10, y: 0, width: 40, height: 13)).boundingRect
    #expect(abs(drawn.midX - 30) < 0.1 && abs(drawn.midY - 6.5) < 0.1 && drawn.width < 13, "\(drawn)")
}

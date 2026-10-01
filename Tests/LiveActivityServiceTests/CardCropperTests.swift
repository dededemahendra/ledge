import Testing
import CoreGraphics
import Foundation
@testable import LiveActivityService

/// A popover window capture: transparent, with an opaque card inside.
private func window() -> CGImage {
    let context = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: 300, height: 200))
    // A faint shadow the bounds must ignore.
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
    context.fill(CGRect(x: 10, y: 60, width: 220, height: 100))
    // The card: Core Graphics y runs up, so y=90 here is top-down y=30.
    context.setFillColor(CGColor(red: 0.6, green: 0.2, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 20, y: 90, width: 200, height: 80))
    return context.makeImage()!
}

@Test func theCardIsTheOpaquePartTopDown() {
    #expect(CardCropper.opaqueBounds(of: window()) == CGRect(x: 20, y: 30, width: 200, height: 80))
}

@Test func theCardIsSlicedIntoTeamsScoreAndWhole() {
    let frame = CardCropper.frame(from: window(), scale: 2)!
    #expect(frame.whole.size == CGSize(width: 100, height: 40), "the card at its own point size")
    #expect(frame.leading.size == CGSize(width: 29, height: 24), "a 60×50 px slice fitted to the ear's 24 pt")
    #expect(frame.trailing.size == CGSize(width: 29, height: 24))
    #expect(frame.center.size == CGSize(width: 35, height: 22), "an 80×50 px slice fitted to the caption's 22 pt")
}

@Test func nothingOpaqueIsNoCard() {
    let context = CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: 50, height: 50))
    #expect(CardCropper.frame(from: context.makeImage()!, scale: 2) == nil)
}

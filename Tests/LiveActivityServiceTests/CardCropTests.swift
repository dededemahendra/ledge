import Testing
import AppKit
import CoreGraphics
import Foundation
@testable import LiveActivityService

/// A window capture: transparent, with an opaque card in it.
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

@Test func aCrestIsCutAtItsOwnRectangleAndDrawnRound() {
    let card = window().cropping(to: CardCropper.opaqueBounds(of: window())!)!
    // The card is 200×80 px at 2x, so 100×40 pt; a 20 pt crest at (10, 5).
    let crest = CardCropper.crest(from: card, at: CGRect(x: 10, y: 5, width: 20, height: 20), scale: 2, size: 24)!
    #expect(crest.size == CGSize(width: 24, height: 24))
    let image = NSBitmapImageRep(data: crest.png)!
    #expect(image.pixelsWide == 48 && image.pixelsHigh == 48, "cut at the screen's scale")
    #expect(image.colorAt(x: 24, y: 24)!.alphaComponent > 0.9, "the middle is the crest")
    #expect(image.colorAt(x: 1, y: 1)!.alphaComponent < 0.1, "the corners are rounded away")
}

@Test func aCrestOutsideTheCardIsNoCrest() {
    let card = window().cropping(to: CardCropper.opaqueBounds(of: window())!)!
    #expect(CardCropper.crest(from: card, at: CGRect(x: 400, y: 400, width: 20, height: 20), scale: 2, size: 24) == nil)
    #expect(CardCropper.crest(from: card, at: CGRect(x: 0, y: 0, width: 0.2, height: 0.2), scale: 2, size: 24) == nil)
}

import Testing
import CoreGraphics
import Foundation
@testable import LiveActivityService

/// A 92×48 pill: menu bar material outside, a dark capsule inside, and
/// optionally a white mark in the middle.
private func pill(withMark: Bool) -> CGImage {
    let w = 92, h = 48
    let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.55, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    context.setFillColor(CGColor(red: 0.11, green: 0.16, blue: 0.18, alpha: 1))
    context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: 24, cornerHeight: 24, transform: nil))
    context.fillPath()
    if withMark {
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 36, y: 18, width: 20, height: 12))
    }
    return context.makeImage()!
}

private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let data = image.dataProvider!.data! as Data
    let i = (y * image.bytesPerRow) + x * 4
    return (data[i], data[i + 1], data[i + 2], data[i + 3])
}

@Test func theFillAndTheRimGoAndTheMarkStays() {
    let keyed = PillKeyer.key(pill(withMark: true))!
    #expect(keyed.hasContent)
    #expect(pixel(keyed.image, 46, 24).a == 255, "the mark is opaque")
    #expect(pixel(keyed.image, 46, 24).r == 255)
    #expect(pixel(keyed.image, 20, 24).a == 0, "the fill is transparent")
    #expect(pixel(keyed.image, 1, 1).a == 0, "the corner outside the capsule is transparent")
    #expect(pixel(keyed.image, 46, 0).a == 0, "the rim is transparent")
}

@Test func anEmptyPillHasNoContent() {
    let keyed = PillKeyer.key(pill(withMark: false))!
    #expect(!keyed.hasContent)
    #expect(pixel(keyed.image, 46, 24).a == 0)
}

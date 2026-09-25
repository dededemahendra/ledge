import Testing
import AppKit
import SwiftUI
@testable import NotchKit

@MainActor
private func solidImage(_ color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: 8, height: 8))
    image.lockFocus()
    color.setFill()
    NSRect(x: 0, y: 0, width: 8, height: 8).fill()
    image.unlockFocus()
    return image
}

@MainActor
@Test func missingOrUndecodableArtworkFallsBack() {
    #expect(ArtworkAccent.accent(from: nil) == ArtworkAccent.fallback)
    #expect(ArtworkAccent.accent(from: Data([0x00, 0x01, 0x02])) == ArtworkAccent.fallback)
}

@MainActor
@Test func saturatedArtworkYieldsItsOwnHueNotTheFallback() throws {
    let red = solidImage(NSColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))

    // The averaging primitive itself: a solid image averages to itself.
    let average = try #require(ArtworkAccent.averageColor(of: red))
    let rgb = try #require(average.usingColorSpace(.deviceRGB))
    #expect(rgb.redComponent > 0.6)
    #expect(rgb.greenComponent < 0.3)
    #expect(rgb.blueComponent < 0.3)

    // And the public API keeps the hue rather than falling back.
    let accent = ArtworkAccent.accent(from: try #require(red.tiffRepresentation))
    #expect(accent != ArtworkAccent.fallback)
}

/// Grey has no chroma to tint with — a grey accent on a black card reads as
/// dirt, so near-grey artwork must yield the deliberate fallback colour.
@MainActor
@Test func greyArtworkFallsBackRatherThanTintingGrey() throws {
    let grey = solidImage(NSColor(white: 0.5, alpha: 1))
    #expect(ArtworkAccent.accent(from: try #require(grey.tiffRepresentation)) == ArtworkAccent.fallback)
}

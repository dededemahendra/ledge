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
    // Two bright figures where a score card puts its score.
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 90, y: 135, width: 20, height: 20))
    context.fill(CGRect(x: 130, y: 135, width: 20, height: 20))
    return context.makeImage()!
}

@Test func theCardIsTheOpaquePartTopDown() {
    #expect(CardCropper.opaqueBounds(of: window()) == CGRect(x: 20, y: 30, width: 200, height: 80))
}

@Test func theCardIsSlicedIntoACrestAndFigurePairPerEar() {
    let frame = CardCropper.frame(from: window(), scale: 2)!
    #expect(frame.whole.size == CGSize(width: 100, height: 40), "the card at its own point size")
    #expect(frame.leading.size.height == CardCropper.earHeight)
    #expect(frame.trailing.size.height == CardCropper.earHeight)
    #expect(frame.leading.size.width > CardCropper.earHeight, "a crest AND its figure, so wider than tall")
}

/// The pair is crest-outward: the figure sits toward the notch on each
/// side, as the phone's island draws a scoreline around its camera.
@Test func aPairPutsTheCrestOutwardAndTheFigureInward() {
    let crest = solid(red: 0.8)
    let figure = solid(red: 1)
    let home = CardCropper.pair(crest: crest, figure: figure, figureLeading: false)!
    let away = CardCropper.pair(crest: crest, figure: figure, figureLeading: true)!
    #expect(home.width == away.width && home.height == crest.height)
    #expect(home.width > crest.width, "the figure widens the pair")
    // The crest is drawn round, so a pair's outer top corner is clear.
    #expect(alpha(home, x: 0, y: 0) == 0, "home crest leads, its corner rounded away")
    #expect(alpha(away, x: away.width - 1, y: 0) == 0, "away crest trails")
    #expect(CardCropper.pair(crest: crest, figure: nil, figureLeading: false)!.width == crest.width,
            "no figure, no widening")
}

private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
    let data = image.dataProvider!.data! as Data
    return data[(y * image.bytesPerRow) + x * 4 + 3]
}

@Test func theScoreIsKeyedToItsBrightFiguresAndTrimmedToThem() {
    // A dark gradient with two white blocks, as a score card draws it.
    let context = CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.3, green: 0.1, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 20, y: 15, width: 10, height: 20))
    context.fill(CGRect(x: 70, y: 15, width: 10, height: 20))
    let keyed = CardCropper.keyedBright(context.makeImage()!)!
    #expect(keyed.width == 60 && keyed.height == 20, "trimmed to the two figures")
    #expect(CardCropper.keyedBright(solid(red: 0.3)) == nil, "nothing bright is no score")
}

private func solid(red: CGFloat) -> CGImage {
    let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: red, green: 0.1, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
    return context.makeImage()!
}

@Test func nothingOpaqueIsNoCard() {
    let context = CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: 50, height: 50))
    #expect(CardCropper.frame(from: context.makeImage()!, scale: 2) == nil)
}

@Test func onlyTheWhiteFiguresSurviveTheScoreKey() {
    let context = CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.3, green: 0.1, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 10, y: 15, width: 10, height: 20))
    // A bright but colourful mark between the figures — the ball.
    context.setFillColor(CGColor(red: 1, green: 0.6, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 45, y: 20, width: 10, height: 10))
    let keyed = CardCropper.keyedBright(context.makeImage()!)!
    #expect(keyed.width == 10 && keyed.height == 20, "the figure alone; the colourful mark is gone")
}

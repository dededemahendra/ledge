import Testing
import SwiftUI
import AppKit
@testable import SettingsKit
@testable import NotchKit

/// The box around every near-black, opaque pixel of a rendered strip, in
/// points: the island (and, on a MacBook, its outer fillets).
@MainActor
private func islandBox(_ strip: PreviewStrip, width: CGFloat) -> CGRect {
    let renderer = ImageRenderer(content: strip.frame(width: width))
    renderer.scale = 2
    guard let image = renderer.cgImage else { return .null }
    let w = image.width, h = image.height, row = w * 4
    var pixels = [UInt8](repeating: 0, count: h * row)
    guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .null }
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var box = CGRect.null
    for y in 0..<h {
        for x in 0..<w {
            let i = y * row + x * 4
            if pixels[i + 3] > 200, pixels[i] < 12, pixels[i + 1] < 12, pixels[i + 2] < 12 {
                box = box.union(CGRect(x: CGFloat(x) / 2, y: CGFloat(y) / 2, width: 0.5, height: 0.5))
            }
        }
    }
    return box
}

/// The strip draws the real island where the screen has it: at the top,
/// centred, the one-activity shape for a battery blip, on a MacBook's
/// notch and on the pill. Run with no desktop picture (Review Focus 2):
/// the gradient behind it.
@MainActor
@Test func theStripDrawsTheRealIslandAtTheTopCentre() {
    let screens: [(String, NotchMetrics)] = [
        ("notch", NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 179, height: 32))),
        ("pill", NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 44, height: 32), isVirtual: true)),
    ]
    let width: CGFloat = 520
    for (name, metrics) in screens {
        let director = PreviewDirector(scenes: [.battery], isOn: { _ in true })
        let strip = PreviewStrip(director: director, height: PreviewStrip.shortHeight, metrics: metrics, wallpaper: nil) {
            PreviewContent()
        }
        let box = islandBox(strip, width: width)
        let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
        let want = NotchShape(metrics.oneActivity).path(in: canvas).boundingRect
            .offsetBy(dx: width / 2 - canvas.midX, dy: 0)
        #expect(abs(box.midX - want.midX) < 2, "\(name): centred at \(box.midX), want \(want.midX)")
        let body = metrics.oneActivity.width
        #expect(box.width >= body - 1 && box.width <= want.width + 1,
                "\(name): \(box.width) wide, want between the body \(body) and the outline \(want.width)")
        #expect(abs(box.minY - want.minY) < 1.5 && abs(box.maxY - want.maxY) < 1.5, "\(name): \(box), want \(want)")
    }
}

/// In a pane narrower than the island's 640 pt canvas, the strip takes the
/// pane's width and crops the canvas; it does not widen the pane.
@MainActor
@Test func aNarrowStripCropsTheCanvasInsteadOfWideningThePane() {
    let director = PreviewDirector(scenes: [.battery], isOn: { _ in true })
    let strip = PreviewStrip(director: director, height: PreviewStrip.shortHeight,
                             metrics: NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 179, height: 32)),
                             wallpaper: nil) { PreviewContent() }
    let renderer = ImageRenderer(content: strip)
    renderer.proposedSize = ProposedViewSize(width: 300, height: nil)
    renderer.scale = 1
    #expect(renderer.cgImage?.width == 300)
}

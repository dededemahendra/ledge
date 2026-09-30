// Draws the app icon (2026-09-30): the island, hanging from the top of a
// dark rounded square, its two ear marks lit. Run `make icon` to regenerate
// Resources/Ledge.icns; nothing here is hand-edited.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // The macOS icon grid: an 824pt square centred in 1024, corner ~185.
    let square = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squarePath = CGPath(roundedRect: square, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Shadow, like the system's own icons cast.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squarePath)
    ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Body: slate at the top to near-black at the bottom, a screen at rest.
    ctx.saveGState()
    ctx.addPath(squarePath)
    ctx.clip()
    let colors = [CGColor(red: 0.20, green: 0.22, blue: 0.29, alpha: 1), CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: square.midX, y: square.minY), end: CGPoint(x: square.midX, y: square.maxY), options: [])
    // A soft top-left light.
    let light = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: CGPoint(x: square.minX + 180, y: square.minY + 120), startRadius: 0,
                           endCenter: CGPoint(x: square.minX + 180, y: square.minY + 120), endRadius: 620, options: [])
    // The island: black, hanging from the top edge, rounded below only.
    let island = CGRect(x: square.midX - 250, y: square.minY, width: 500, height: 190)
    let islandPath = CGMutablePath()
    islandPath.move(to: CGPoint(x: island.minX, y: island.minY))
    islandPath.addLine(to: CGPoint(x: island.maxX, y: island.minY))
    islandPath.addLine(to: CGPoint(x: island.maxX, y: island.maxY - 70))
    islandPath.addArc(tangent1End: CGPoint(x: island.maxX, y: island.maxY), tangent2End: CGPoint(x: island.maxX - 70, y: island.maxY), radius: 70)
    islandPath.addLine(to: CGPoint(x: island.minX + 70, y: island.maxY))
    islandPath.addArc(tangent1End: CGPoint(x: island.minX, y: island.maxY), tangent2End: CGPoint(x: island.minX, y: island.maxY - 70), radius: 70)
    islandPath.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 24, color: CGColor(gray: 0, alpha: 0.55))
    ctx.addPath(islandPath)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    // The ears: a glyph-sized disc left, a value-sized bar right.
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.92))
    ctx.fillEllipse(in: CGRect(x: island.minX + 74, y: island.midY - 34, width: 68, height: 68))
    ctx.addPath(CGPath(roundedRect: CGRect(x: island.maxX - 74 - 150, y: island.midY - 20, width: 150, height: 40), cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    return true
}

let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))

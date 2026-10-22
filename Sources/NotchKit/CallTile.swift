import AppKit

/// A service's stand-in icon (2026-10-22): its glyph in white on a rounded
/// tile of its colour, for a meeting service without a Mac app (Meet). No
/// third-party logo is bundled.
public enum CallTile {
    @MainActor
    public static func png(symbol: String, color: NSColor, side: CGFloat = 64) -> Data? {
        let pixels = Int(side)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: side * 0.22, yRadius: side * 0.22).fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.42, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            let size = glyph.size
            glyph.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

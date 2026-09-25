import AppKit
import SwiftUI

/// Derives one accent colour from album artwork — the image's average colour,
/// clamped so it stays legible on the island's near-black card — the way
/// Apple Music tints its own chrome from the current sleeve.
///
/// Deliberately cheap: the image is drawn once into a single pixel (the GPU
/// does the averaging), only when the track changes, and the result is cached
/// by the caller. Nothing here runs per-frame.
public enum ArtworkAccent {
    /// Used when there is no artwork, or when the artwork averages to a
    /// near-grey with no identity (white sleeves, B&W photography) — a grey
    /// accent on a black card reads as dirt, not as a tint.
    public static let fallback = Color.teal

    public static func accent(from data: Data?) -> Color {
        guard
            let data,
            let image = NSImage(data: data),
            let average = averageColor(of: image),
            let rgb = average.usingColorSpace(.deviceRGB)
        else { return fallback }

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // No chroma to speak of — prefer the fallback's deliberate colour.
        guard saturation >= 0.15 else { return fallback }

        // Floor brightness so the tint reads against black; cap saturation so
        // it doesn't glow like a neon sign next to white text.
        return Color(nsColor: NSColor(
            hue: hue,
            saturation: min(saturation, 0.85),
            brightness: max(brightness, 0.65),
            alpha: 1
        ))
    }

    /// Average via a 1×1 draw — no CoreImage dependency, one allocation.
    static func averageColor(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        guard let context = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let alpha = CGFloat(bytes[3]) / 255
        guard alpha > 0.01 else { return nil }

        // Un-premultiply before handing back a plain colour.
        return NSColor(
            red: CGFloat(bytes[0]) / 255 / alpha,
            green: CGFloat(bytes[1]) / 255 / alpha,
            blue: CGFloat(bytes[2]) / 255 / alpha,
            alpha: 1
        )
    }
}

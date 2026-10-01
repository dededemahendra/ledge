import CoreGraphics
import Foundation

/// Lifts the activity's content off the pill (2026-10-01): the menu bar
/// draws the pill as a capsule of its own material — a grey-teal over
/// this wallpaper — which on the island's black reads as a blob. The
/// fill colour is sampled just inside the capsule's rim and every pixel
/// near it is made transparent, so only what the phone draws (white
/// text, a tinted glyph) lands on the island. Pixels outside an inset
/// capsule go too: the rim's anti-aliasing blends the menu bar in.
public enum PillKeyer {
    public struct Result {
        public let image: CGImage
        /// Whether anything survived the key — an empty pill is a blob
        /// with nothing in it, and the island shows nothing for it.
        public let hasContent: Bool
    }

    /// Below this distance from the fill (0…255 per channel, max over
    /// channels) a pixel is fill; above `opaque` it is content.
    static let transparent = 14
    static let opaque = 48
    /// Pixels inside the inset capsule that must be content for the frame
    /// to count as having any, as a fraction of the capsule.
    static let contentFraction = 0.004

    public static func key(_ image: CGImage) -> Result? {
        let width = image.width, height = image.height
        guard width > 4, height > 4,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let inset = max(2.0, Double(height) * 0.06)
        let radius = Double(height) / 2 - inset
        func inside(_ x: Int, _ y: Int) -> Bool {
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            let cy = Double(height) / 2
            let left = inset + radius, right = Double(width) - inset - radius
            if px < left { return (px - left) * (px - left) + (py - cy) * (py - cy) <= radius * radius }
            if px > right { return (px - right) * (px - right) + (py - cy) * (py - cy) <= radius * radius }
            return abs(py - cy) <= radius
        }

        // The fill: the median of a ring of samples just inside the rim.
        var reds: [Int] = [], greens: [Int] = [], blues: [Int] = []
        let ringY = [Int(inset) + 1, height - Int(inset) - 2]
        for y in ringY {
            for x in stride(from: Int(inset + radius), through: width - Int(inset + radius) - 1, by: 3) where inside(x, y) {
                let i = (y * width + x) * 4
                reds.append(Int(pixels[i])); greens.append(Int(pixels[i + 1])); blues.append(Int(pixels[i + 2]))
            }
        }
        for x in [Int(inset) + 1, width - Int(inset) - 2] {
            let y = height / 2
            let i = (y * width + x) * 4
            reds.append(Int(pixels[i])); greens.append(Int(pixels[i + 1])); blues.append(Int(pixels[i + 2]))
        }
        guard !reds.isEmpty else { return nil }
        func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }
        let fill = (median(reds), median(greens), median(blues))

        var content = 0, area = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard inside(x, y) else {
                    pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
                    continue
                }
                area += 1
                let distance = max(abs(Int(pixels[i]) - fill.0), abs(Int(pixels[i + 1]) - fill.1), abs(Int(pixels[i + 2]) - fill.2))
                let alpha = min(1, max(0, Double(distance - transparent) / Double(opaque - transparent)))
                if alpha > 0.5 { content += 1 }
                pixels[i] = UInt8(Double(pixels[i]) * alpha)
                pixels[i + 1] = UInt8(Double(pixels[i + 1]) * alpha)
                pixels[i + 2] = UInt8(Double(pixels[i + 2]) * alpha)
                pixels[i + 3] = UInt8(255 * alpha)
            }
        }
        guard let keyed = context.makeImage() else { return nil }
        return Result(image: keyed, hasContent: area > 0 && Double(content) / Double(area) >= contentFraction)
    }
}

import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// The system's card for the activity, copied (2026-10-01). The card —
/// a match's flags, score and clock, as the phone renders it — exists
/// only in the popover `MenuBarAgent` makes when the pill is pressed and
/// destroys when it closes; the compact pill stays blank for apps the Mac
/// cannot render. So the island peeks: presses the pill, captures the
/// popover's window the moment it is on screen, presses again to close
/// it. A flash of the system card, about a fifth of a second.
public struct CardFrame: Sendable, Equatable {
    /// The card itself, at its own point size.
    public let whole: PillImage
    /// The card's left and right thirds, top part — a home team and the
    /// away team — sized for an ear.
    public let leading: PillImage
    public let trailing: PillImage
    /// The middle, top part — the score — sized for the caption row.
    public let center: PillImage

    public init(whole: PillImage, leading: PillImage, trailing: PillImage, center: PillImage) {
        self.whole = whole
        self.leading = leading
        self.trailing = trailing
        self.center = center
    }
}

/// Pure slicing of a captured popover window into a `CardFrame`.
public enum CardCropper {
    /// The card's opaque bounds in a window capture that has transparent
    /// margins (the popover's shadow is faint; `threshold` ignores it).
    public static func opaqueBounds(of image: CGImage, threshold: UInt8 = 200) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= threshold {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // The bitmap's first row in memory is the image's top row, so these
        // are already the top-down coordinates `cropping(to:)` expects.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Where a score card keeps its badges and its score, measured on the
    /// real thing (2026-10-01): a round crest a sixth of the way in on
    /// each side, a third of the way down, about a tenth of the width
    /// across; the score between them, in the band above the clock. The
    /// crest is cut as a square and the island's ear clips it round, so
    /// the gradient behind it never reaches the island; the score is
    /// keyed to its bright figures and trimmed to them, so what lands
    /// under the notch is white digits on black, the island's own idiom.
    public static let crestCentreX = 0.165
    public static let crestCentreY = 0.33
    public static let crestSize = 0.092
    public static let scoreBand = CGRect(x: 0.30, y: 0.14, width: 0.40, height: 0.38)
    public static let earHeight: CGFloat = 24
    public static let captionHeight: CGFloat = 19
    /// Below this luminance a score pixel is background.
    static let scoreFloor = 110.0
    static let scoreCeiling = 190.0
    /// And above this much colour it is not a figure: a score is drawn in
    /// white, while the little ball between the numbers is not, and keyed
    /// it came through as a speck of dirt (2026-10-01).
    static let scoreSaturationFloor = 0.25
    static let scoreSaturationCeiling = 0.45

    /// Slices a window capture (`scale` pixels per point) into a frame.
    public static func frame(from window: CGImage, scale: CGFloat) -> CardFrame? {
        guard let bounds = opaqueBounds(of: window), bounds.width >= 40 * scale, bounds.height >= 24 * scale,
              let card = window.cropping(to: bounds)
        else { return nil }
        let w = CGFloat(card.width), h = CGFloat(card.height)
        let side = max(2, (w * crestSize).rounded())
        func crest(at centreX: Double) -> CGImage? {
            card.cropping(to: CGRect(x: (w * centreX - side / 2).rounded(), y: (h * crestCentreY - side / 2).rounded(),
                                     width: side, height: side).integral)
        }
        let band = CGRect(x: (w * scoreBand.minX).rounded(), y: (h * scoreBand.minY).rounded(),
                          width: (w * scoreBand.width).rounded(), height: (h * scoreBand.height).rounded()).integral
        guard let left = crest(at: crestCentreX), let right = crest(at: 1 - crestCentreX),
              let middle = card.cropping(to: band), let score = keyedBright(middle),
              let whole = encode(card, size: CGSize(width: w / scale, height: h / scale)),
              let leading = encode(left, size: CGSize(width: earHeight, height: earHeight)),
              let trailing = encode(right, size: CGSize(width: earHeight, height: earHeight)),
              let center = encode(score, size: fitted(score, height: captionHeight))
        else { return nil }
        return CardFrame(whole: whole, leading: leading, trailing: trailing, center: center)
    }

    /// The bright figures of a slice on transparency, trimmed to them —
    /// a score lifted off whatever gradient the card draws behind it.
    /// `nil` when there is nothing bright enough to be a figure.
    static func keyedBright(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            let luma = r * 0.299 + g * 0.587 + b * 0.114
            let high = max(r, g, b), low = min(r, g, b)
            let saturation = high > 0 ? (high - low) / high : 0
            let colour = min(1, max(0, (saturation - scoreSaturationFloor) / (scoreSaturationCeiling - scoreSaturationFloor)))
            let alpha = min(1, max(0, (luma - scoreFloor) / (scoreCeiling - scoreFloor))) * (1 - colour)
            pixels[i] = UInt8(Double(pixels[i]) * alpha)
            pixels[i + 1] = UInt8(Double(pixels[i + 1]) * alpha)
            pixels[i + 2] = UInt8(Double(pixels[i + 2]) * alpha)
            pixels[i + 3] = UInt8(255 * alpha)
        }
        guard let keyed = context.makeImage(), let bounds = opaqueBounds(of: keyed, threshold: 128),
              bounds.width >= 2, bounds.height >= 2
        else { return nil }
        return keyed.cropping(to: bounds)
    }

    static func fitted(_ image: CGImage, height: CGFloat) -> CGSize {
        CGSize(width: (CGFloat(image.width) / CGFloat(image.height) * height).rounded(), height: height)
    }

    private static func encode(_ image: CGImage, size: CGSize) -> PillImage? {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        return PillImage(png: png, size: size, hasContent: true)
    }
}

/// Finds and captures the popover once it is up.
enum CardPeek {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "live-activity")
    static let timeout: Duration = .milliseconds(800)
    static let step: Duration = .milliseconds(50)

    /// The popover's window: `MenuBarAgent`'s, on screen, hanging below
    /// the pill and wider than the pill.
    static func popover(below pill: CGRect) async -> SCWindow? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        return content.windows.first { window in
            window.owningApplication?.bundleIdentifier == PillLocator.host
                && window.frame.minY >= pill.maxY - 4 && window.frame.minY < pill.maxY + 40
                && window.frame.width > pill.width * 2 && window.frame.height > 40
                && window.frame.midX > pill.minX - 400 && window.frame.midX < pill.maxX + 400
        }
    }

    static func capture(_ window: SCWindow, scale: CGFloat) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

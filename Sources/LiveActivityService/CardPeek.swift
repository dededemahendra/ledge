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

    /// Where a score card keeps its teams and score: the left and right
    /// 30 % hold a crest and a name, the middle 40 % the score and the
    /// clock; the top 62 % is the crests-and-score row.
    public static let sideFraction = 0.30
    public static let topFraction = 0.62
    public static let earHeight: CGFloat = 24
    public static let captionHeight: CGFloat = 22

    /// Slices a window capture (`scale` pixels per point) into a frame.
    public static func frame(from window: CGImage, scale: CGFloat) -> CardFrame? {
        guard let bounds = opaqueBounds(of: window), bounds.width >= 40 * scale, bounds.height >= 24 * scale,
              let card = window.cropping(to: bounds)
        else { return nil }
        let w = CGFloat(card.width), h = CGFloat(card.height)
        let top = (h * topFraction).rounded()
        let side = (w * sideFraction).rounded()
        guard let left = card.cropping(to: CGRect(x: 0, y: 0, width: side, height: top)),
              let right = card.cropping(to: CGRect(x: w - side, y: 0, width: side, height: top)),
              let middle = card.cropping(to: CGRect(x: side, y: 0, width: w - 2 * side, height: top)),
              let whole = encode(card, size: CGSize(width: w / scale, height: h / scale)),
              let leading = encode(left, size: fitted(left, height: earHeight)),
              let trailing = encode(right, size: fitted(right, height: earHeight)),
              let center = encode(middle, size: fitted(middle, height: captionHeight))
        else { return nil }
        return CardFrame(whole: whole, leading: leading, trailing: trailing, center: center)
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
